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
    let reaction: String
}

/// 選んだ選択肢でひよりの気持ちがどう動いたかを判定する。本番はローカルLLM、テストではスタブに差し替える
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
}

/// 「ときめき +1 / 信頼 0 / ノリ +2」の形の判定を読む
nonisolated enum JudgmentParser {
    /// 全角の数字と符号は半角として読む（「ノリ」まで半角カナにしないよう、文字を絞って変換する）
    private static let halfwidth = Dictionary(uniqueKeysWithValues: zip("０１２３４５６７８９＋－−", "0123456789+--"))

    /// 3つの軸がすべて読めたときだけ返す。値は Feelings.deltaRange に収める
    static func parse(_ raw: String) -> Feelings? {
        let text = String(
            raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
                .map { halfwidth[$0] ?? $0 }
        )
        var feelings = Feelings()
        for axis in Axis.allCases {
            let pattern = axis.label + #"\s*[:：]?\s*([+-]?\s*\d+)"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
            let digits = text[range].dropFirst(axis.label.count)
                .filter { $0.isNumber || $0 == "-" }
            guard let value = Int(digits) else { return nil }
            feelings[axis] = value.clamped(to: Feelings.deltaRange)
        }
        return feelings
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
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.judgeInstructions(for: request.heroine))
        let response = try await session.respond(
            to: PromptBuilder.judgePrompt(request),
            options: GenerationOptions(
                sampling: .random(probabilityThreshold: 0.9, seed: .random(in: 0...UInt64.max)),
                temperature: 0.7,
                maximumResponseTokens: Self.judgmentTokenLimit
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
