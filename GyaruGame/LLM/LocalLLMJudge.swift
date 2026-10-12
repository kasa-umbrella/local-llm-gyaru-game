import Foundation
import FoundationModels
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// MLX で動かすローカルLLM（Qwen3.5）による生成。
///
/// mlx-swift-lm の MLXFoundationModels で MLX のモデルを FoundationModels.LanguageModel として扱うので、
/// LanguageModelSession や @Generable はそのまま使える。Apple のガードレールはかからず、
/// 構造化出力は文法で縛られるため、1回の生成で1ターン分（セリフ・表情・選択肢・好感度）をまとめて出せる。
final class LocalLLMDialogueGenerator: DialogueGenerating {
    /// Mac は 9B（約6GB）、iPhone はメモリの都合で 4B（約3GB）
    #if os(macOS)
    static let modelID = "mlx-community/Qwen3.5-9B-MLX-4bit"
    static let modelDisplayName = "Qwen3.5 9B"
    static let approximateDownloadSize = "約6GB"
    #else
    static let modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    static let modelDisplayName = "Qwen3.5 4B"
    static let approximateDownloadSize = "約3GB"
    #endif

    let model: MLXLanguageModel

    init(modelID: String = LocalLLMDialogueGenerator.modelID) {
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

    func prewarm(for heroine: Heroine) {
        let model = model
        Task { try? await model.preload() }
    }

    /// 出力が途中で途切れて型に変換できなかったときに作り直す回数
    static let parseRetryLimit = 1
    /// 「うん、うん、うん…」のような繰り返しで止まらなくなるのを防ぐ上限
    static let lineTokenLimit = 240
    static let singleChoiceTokenLimit = 160
    /// 選択肢を作るときの temperature。使えない文が出たら次の値で作り直す（同じ写しが繰り返し出るのを防ぐ）
    static let choiceTemperatures = [0.6, 0.85, 1.0]

    /// まずヒロインのセリフを生成し、続けて主人公の選択肢を方向性ごとに1つずつ生成する。
    /// 1回で両方を出させると、ヒロインのセリフを選択肢にコピーするなど視点が混ざるため分けている。
    func streamTurn(_ request: TurnRequest) -> AsyncThrowingStream<TurnDraft, Error> {
        let model = model
        let heroine = request.heroine
        let needsChoices = request.directive.phase != .closing

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lines = try await Self.withParseRetry {
                        try await Self.streamLines(model: model, request: request) { partial in
                            continuation.yield(TurnDraft(lines: partial, choices: [], isFinal: false))
                        }
                    }
                    let choices = needsChoices
                        ? (try? await Self.withParseRetry { try await Self.choices(model: model, request: request, heroineLine: lines.map(\.text).joined()) }) ?? []
                        : []
                    continuation.yield(TurnDraft(lines: lines, choices: choices, isFinal: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func streamLines(
        model: MLXLanguageModel,
        request: TurnRequest,
        onPartial: ([DialogueLine]) -> Void
    ) async throws -> [DialogueLine] {
        let speaker = request.heroine.name
        let session = LanguageModelSession(
            model: model,
            instructions: PromptBuilder.instructions(for: request.heroine, style: .structuredLine)
        )
        let stream = session.streamResponse(
            to: PromptBuilder.turnPrompt(request),
            generating: GeneratedReply.self,
            options: sampling(temperature: 0.6, maximumResponseTokens: lineTokenLimit)
        )
        var last: GeneratedContent?
        for try await snapshot in stream {
            last = snapshot.rawContent
            let lines = (snapshot.content.lines ?? []).compactMap { partial -> DialogueLine? in
                guard let text = partial.text, !text.isEmpty else { return nil }
                return DialogueLine(speaker: speaker, text: text, emotion: partial.emotion ?? .normal)
            }
            if !lines.isEmpty { onPartial(lines) }
        }
        guard let last else { throw CancellationError() }
        return try GeneratedReply(last).lines.map {
            DialogueLine(speaker: speaker, text: GeneratedTextCleaner.choice($0.text), emotion: $0.emotion)
        }
    }

    /// 選択肢を方向性ごとに1つずつ作る。使えない文（セリフの写し・指示語の写し・重複・壊れた出力）は
    /// temperature を上げて作り直し、それでも3つそろわなければ空を返して呼び出し側の定型の選択肢に任せる
    private static func choices(model: MLXLanguageModel, request: TurnRequest, heroineLine: String) async throws -> [ChoiceOption] {
        var options: [ChoiceOption] = []
        for tone in ChoiceTone.plannedSet() {
            for temperature in choiceTemperatures {
                let others = options.map(\.text)
                let candidate: ChoiceOption
                do {
                    candidate = try await singleChoice(model: model, request: request, heroineLine: heroineLine, tone: tone, avoiding: others, temperature: temperature)
                } catch {
                    #if DEBUG
                    print("[LocalLLM] choice(\(tone)) error: \(error)")
                    #endif
                    continue
                }
                if let reason = GeneratedTextCleaner.rejectionReason(for: candidate.text, heroineLine: heroineLine, others: others) {
                    #if DEBUG
                    print("[LocalLLM] choice(\(tone)) rejected (\(reason)): \(candidate.text)")
                    #endif
                    continue
                }
                options.append(candidate)
                break
            }
        }
        return options.count == 3 ? options : []
    }

    /// 選択肢は自由な文1行なので文字列で生成する。
    /// mlx-swift-lm の構造化出力は temperature や乱数の種を変えても毎回同じ文になり、作り直しが効かないため。
    /// 好感度は AffectionEngine の基準値と相性表に任せ、LLM の微調整は使わない
    private static func singleChoice(model: MLXLanguageModel, request: TurnRequest, heroineLine: String, tone: ChoiceTone, avoiding existing: [String], temperature: Double) async throws -> ChoiceOption {
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.choiceInstructions)
        let response = try await session.respond(
            to: PromptBuilder.structuredSingleChoicePrompt(
                heroine: request.heroine,
                directive: request.directive,
                recentLog: request.recentLog,
                heroineLine: heroineLine,
                tone: tone,
                avoiding: existing
            ),
            options: sampling(temperature: temperature, maximumResponseTokens: singleChoiceTokenLimit)
        )
        let text = GeneratedTextCleaner.choices(GeneratedTextCleaner.removingReasoning(response.content), count: 1).first ?? ""
        return ChoiceOption(text: text, tone: tone, suggestedDelta: 0)
    }

    /// 毎回ちがう乱数の種で上位90%からサンプリングする。
    /// 種を指定しないと同じ入力から毎回同じ文が出て、作り直しても同じ失敗を繰り返すため
    private static func sampling(temperature: Double, maximumResponseTokens: Int) -> GenerationOptions {
        GenerationOptions(
            sampling: .random(probabilityThreshold: 0.9, seed: .random(in: 0...UInt64.max)),
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
    }

    /// 出力が途中で途切れて型に変換できなかったときなどに作り直す（キャンセルは除く）
    private static func withParseRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard !(error is CancellationError), !Task.isCancelled, attempt < parseRetryLimit else { throw error }
                attempt += 1
            }
        }
    }

    func summarize(_ request: SummaryRequest) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.summaryInstructions)
        let response = try await session.respond(
            to: PromptBuilder.summaryPrompt(request),
            options: GenerationOptions(temperature: 0.3)
        )
        return String(response.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
}
