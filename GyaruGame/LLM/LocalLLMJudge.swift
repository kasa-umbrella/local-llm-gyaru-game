import Foundation
import FoundationModels
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// 判定役に渡す材料
nonisolated struct JudgeRequest: Sendable {
    let heroine: Heroine
    let scene: SceneDefinition
    let mood: Mood
    let feelings: Feelings
    /// このシーンで選択肢が出るまでの流れ（地の文も含む）
    let recentLines: [DialogueLine]
    let playerLine: String
    /// 選択肢に対するひよりの反応。自由入力のときは nil（反応はこの判定で選ぶので、まだない）
    let reaction: String?

    var isFreeInput: Bool {
        reaction == nil
    }
}

/// 選んだ選択肢や入力した一言でひよりの気持ちがどう動いたかを判定する。本番はローカルLLM、テストではスタブに差し替える
protocol FeelingJudging: AnyObject {
    func prewarm()
    /// 判定の生の出力（JudgmentParser で読む前の文字列）
    func judge(_ request: JudgeRequest) async throws -> String
}

extension FeelingJudging {
    /// 読み取れる判定が返るまで1回だけ作り直す。それでもだめなら変化なしにする
    func judgedDelta(_ request: JudgeRequest, attempts: Int = 2) async -> Feelings {
        for _ in 0..<attempts {
            guard !Task.isCancelled else { break }
            guard let raw = try? await judge(request) else { continue }
            if let delta = JudgmentParser.parse(raw) { return delta }
            #if DEBUG
            print("[Judge] unreadable: \(raw)")
            #endif
        }
        return Feelings()
    }

    /// 自由入力の判定。読み取れる判定が返るまで1回だけ作り直し、それでもだめなら当たり障りのない相づちにする。
    /// `timeout` を過ぎても答えが出なければ、待たずに同じ相づちにする
    func judgedFreeInput(_ request: JudgeRequest, attempts: Int = 2, timeout: Duration = FreeInput.judgmentTimeout) async -> FreeInputJudgment {
        // 判定役が呼び出しの中断に応えなくても待たされないよう、判定と時計を別々に走らせて、先に出たほうを使う
        let (results, continuation) = AsyncStream.makeStream(of: FreeInputJudgment?.self)
        let work = Task { continuation.yield(await readFreeInput(request, attempts: attempts)) }
        let clock = Task {
            try? await Task.sleep(for: timeout)
            continuation.yield(nil)
        }
        defer {
            work.cancel()
            clock.cancel()
        }
        var iterator = results.makeAsyncIterator()
        guard let first = await iterator.next(), let judgment = first else { return .fallback }
        return judgment
    }

    private func readFreeInput(_ request: JudgeRequest, attempts: Int) async -> FreeInputJudgment {
        for _ in 0..<attempts {
            guard !Task.isCancelled else { break }
            guard let raw = try? await judge(request) else { continue }
            if let judgment = JudgmentParser.parseFreeInput(raw) { return judgment }
            #if DEBUG
            print("[Judge] unreadable: \(raw)")
            #endif
        }
        return .fallback
    }
}

/// 「ときめき +1 / 信頼 0 / ノリ +2」の形の判定を読む。
/// 自由入力では、頭に「反応: 照れ / 」が付く
nonisolated enum JudgmentParser {
    /// 全角の数字と符号は半角として読む（「ノリ」まで半角カナにしないよう、文字を絞って変換する）
    private static let halfwidth = Dictionary(uniqueKeysWithValues: zip("０１２３４５６７８９＋－−", "0123456789+--"))

    /// 「反応」のあとに続く、反応の種類の名前を探す式
    private static let kindPattern = "反応\\s*[:：]?\\s*(" + ReplyKind.allCases.map(\.label).joined(separator: "|") + ")"

    /// 3つの軸がすべて読めたときだけ返す。値は Feelings.deltaRange に収める
    static func parse(_ raw: String) -> Feelings? {
        parseAxes(in: normalized(raw), allowingMissing: false)
    }

    /// 反応の種類と、少なくとも1つの軸が読めたときだけ返す。読めなかった軸は動かなかったものとして扱う
    /// （自由入力は1行が長く、モデルが最後の軸を書き忘れることがあるため）。
    /// 気持ちは、その反応で上げられる上限に収める
    static func parseFreeInput(_ raw: String) -> FreeInputJudgment? {
        let text = normalized(raw)
        guard let range = text.range(of: kindPattern, options: .regularExpression),
              let kind = ReplyKind.allCases.first(where: { text[range].hasSuffix($0.label) }),
              var delta = parseAxes(in: text, allowingMissing: true) else { return nil }
        for axis in Axis.allCases {
            delta[axis] = min(delta[axis], kind.deltaCeiling)
        }
        return FreeInputJudgment(kind: kind, delta: delta)
    }

    /// 思考（<think>）を取り除き、全角の数字と符号を半角にする
    private static func normalized(_ raw: String) -> String {
        String(
            raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
                .map { halfwidth[$0] ?? $0 }
        )
    }

    /// 軸ごとの値を読む。`allowingMissing` なら、読めない軸は 0 にする（1つも読めなければ nil）
    private static func parseAxes(in text: String, allowingMissing: Bool) -> Feelings? {
        var feelings = Feelings()
        var found = 0
        for axis in Axis.allCases {
            let pattern = axis.label + #"\s*[:：]?\s*([+-]?\s*\d+)"#
            guard let range = text.range(of: pattern, options: .regularExpression),
                  let value = Int(text[range].dropFirst(axis.label.count).filter { $0.isNumber || $0 == "-" }) else {
                if allowingMissing { continue }
                return nil
            }
            feelings[axis] = value.clamped(to: Feelings.deltaRange)
            found += 1
        }
        return found > 0 ? feelings : nil
    }
}

/// MLX で動かすローカルLLM（Qwen3.5）による判定。
///
/// mlx-swift-lm の MLXFoundationModels で MLX のモデルを FoundationModels.LanguageModel として扱うので、
/// LanguageModelSession がそのまま使える。`.reasoning` を宣言していないので、思考（<think>）はライブラリ側で切られる。
final class LocalLLMJudge: FeelingJudging {
    /// Mac は 9B（約6GB）、iPhone はメモリの都合で 4B（約3GB）
    #if os(macOS)
    static let modelID = "mlx-community/Qwen3.5-9B-MLX-4bit"
    static let approximateDownloadSize = "約6GB"
    #else
    static let modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    static let approximateDownloadSize = "約3GB"
    #endif

    /// 判定は1行で済むので短く切る
    static let judgmentTokenLimit = 40
    /// 自由入力は頭に反応の種類が付くぶん、少しだけ長い
    static let freeInputTokenLimit = 64
    /// 自由入力は反応の種類を選ぶ分類なので、選択肢の判定よりブレを小さくする
    static let freeInputTemperature = 0.3

    let model: MLXLanguageModel

    init(modelID: String = LocalLLMJudge.modelID) {
        model = #huggingFaceLanguageModel(
            configuration: ModelConfiguration(id: modelID),
            capabilities: [.guidedGeneration]
        )
    }

    /// 重みのダウンロードと読み込みを先に済ませる（初回は数GBのダウンロードになる）
    func preload() async throws {
        try await model.preload()
    }

    /// モデルがダウンロード済みか（ネットワークには接続しない）
    func isDownloaded() async -> Bool {
        await model.isAvailable
    }

    func prewarm() {
        let model = model
        Task { try? await model.preload() }
    }

    func judge(_ request: JudgeRequest) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.instructions(for: request))
        let response = try await session.respond(
            to: PromptBuilder.judgePrompt(request),
            options: GenerationOptions(
                sampling: .random(probabilityThreshold: 0.9, seed: .random(in: 0...UInt64.max)),
                temperature: request.isFreeInput ? Self.freeInputTemperature : 0.7,
                maximumResponseTokens: request.isFreeInput ? Self.freeInputTokenLimit : Self.judgmentTokenLimit
            )
        )
        return response.content
    }
}

/// ローカルLLMのモデルの準備状況
enum LocalModelState: Equatable {
    /// まだダウンロードしていない
    case notDownloaded
    /// ダウンロード中、またはメモリに読み込み中
    case loading
    case ready
    case failed(String)
}
