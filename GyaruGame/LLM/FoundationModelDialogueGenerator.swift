import Foundation
import FoundationModels

/// Apple Foundation Models（オンデバイス LLM）による生成
final class FoundationModelDialogueGenerator: DialogueGenerating {
    private let model = SystemLanguageModel.default
    private var warmedSession: (heroineID: String, session: LanguageModelSession)?

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    func prewarm(for heroine: Heroine) {
        let session = makeSession(for: heroine)
        session.prewarm()
        warmedSession = (heroine.id, session)
    }

    func streamTurn(_ request: TurnRequest) -> AsyncThrowingStream<TurnDraft, Error> {
        let session = takeSession(for: request.heroine)
        let prompt = PromptBuilder.turnPrompt(request)
        let speaker = request.heroine.name

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(
                        to: prompt,
                        generating: GeneratedTurn.self,
                        options: GenerationOptions(temperature: 0.8)
                    )
                    var last: GeneratedContent?
                    for try await snapshot in stream {
                        last = snapshot.rawContent
                        let lines = (snapshot.content.lines ?? []).compactMap { partial -> DialogueLine? in
                            guard let text = partial.text, !text.isEmpty else { return nil }
                            return DialogueLine(speaker: speaker, text: text, emotion: partial.emotion ?? .normal)
                        }
                        continuation.yield(TurnDraft(lines: lines, choices: [], isFinal: false))
                    }
                    guard let last else { throw CancellationError() }
                    let turn = try GeneratedTurn(last)
                    continuation.yield(TurnDraft(
                        lines: turn.lines.map { DialogueLine(speaker: speaker, text: $0.text, emotion: $0.emotion) },
                        choices: turn.choices.map { ChoiceOption(text: $0.text, tone: $0.tone, suggestedDelta: $0.affectionDelta) },
                        isFinal: true
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func summarize(_ request: SummaryRequest) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.summaryInstructions)
        let response = try await session.respond(
            to: PromptBuilder.summaryPrompt(request),
            generating: GeneratedSummary.self,
            options: GenerationOptions(temperature: 0.3)
        )
        return response.content.summary
    }

    // MARK: - Session

    private func makeSession(for heroine: Heroine) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: PromptBuilder.instructions(for: heroine))
    }

    /// prewarm 済みのセッションがあれば使い、なければ新しく作る。
    /// 1ターン1セッションにして、コンテキストが溢れないようにしている。
    private func takeSession(for heroine: Heroine) -> LanguageModelSession {
        defer { prewarm(for: heroine) }
        if let warmed = warmedSession, warmed.heroineID == heroine.id {
            return warmed.session
        }
        return makeSession(for: heroine)
    }
}

extension SystemLanguageModel.Availability {
    var unavailableMessage: String? {
        switch self {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            "このMacはApple Intelligenceに対応していません。"
        case .unavailable(.appleIntelligenceNotEnabled):
            "システム設定でApple Intelligenceをオンにしてください。"
        case .unavailable(.modelNotReady):
            "モデルを準備中です。しばらく待ってから再度お試しください。"
        case .unavailable:
            "オンデバイスモデルを利用できません。"
        }
    }
}
