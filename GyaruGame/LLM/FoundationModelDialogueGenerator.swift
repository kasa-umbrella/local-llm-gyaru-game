import Foundation
import FoundationModels

/// Apple Foundation Models（オンデバイス LLM）による生成。
///
/// 既定のガードレールは「恋愛ゲームのキャラのセリフを書く」という文脈そのものに反応し、
/// 構造化出力（@Generable）では入力段階でほぼ全て弾かれる。そこで1ターンを次の3段に分けている。
/// 1. セリフ: permissiveContentTransformations の文字列出力（ストリーミング）
/// 2. 選択肢: 同じく文字列出力。方向性はシステムが決めて渡す
/// 3. 表情・好感度: contentTagging の構造化出力。キャラ設定や場面を含まない短い入力だけで判定する
final class FoundationModelDialogueGenerator: DialogueGenerating {
    /// ガードレールの判定は確率的なので、何も表示していない段階で弾かれたときだけ作り直して再挑戦する
    static let guardrailRetryLimit = 2
    static let choiceCount = 3

    private let dialogueModel = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let taggingModel = SystemLanguageModel(useCase: .contentTagging)
    private var warmedSession: (heroineID: String, session: LanguageModelSession)?

    static var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    func prewarm(for heroine: Heroine) {
        let session = makeLineSession(for: heroine)
        session.prewarm()
        warmedSession = (heroine.id, session)
    }

    func streamTurn(_ request: TurnRequest) -> AsyncThrowingStream<TurnDraft, Error> {
        let heroine = request.heroine
        let prompt = PromptBuilder.turnPrompt(request)
        let needsChoices = request.directive.phase != .closing
        let firstSession = takeSession(for: heroine)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await self.streamLine(prompt: prompt, heroine: heroine, firstSession: firstSession) { partial in
                        continuation.yield(TurnDraft(lines: [DialogueLine(speaker: heroine.name, text: partial)], choices: [], isFinal: false))
                    }
                    let emotion = await self.emotion(for: text)
                    let choices = needsChoices
                        ? await self.choices(heroine: heroine, directive: request.directive, heroineLine: text)
                        : []
                    continuation.yield(TurnDraft(
                        lines: [DialogueLine(speaker: heroine.name, text: text, emotion: emotion)],
                        choices: choices,
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
        let session = LanguageModelSession(model: dialogueModel, instructions: PromptBuilder.summaryInstructions)
        let response = try await session.respond(
            to: PromptBuilder.summaryPrompt(request),
            options: GenerationOptions(temperature: 0.3)
        )
        return String(response.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    // MARK: - 1. セリフ

    /// セリフを文字列でストリーミング生成し、整形済みの途中経過を onPartial に渡す。戻り値は整形済みの全文
    private func streamLine(
        prompt: String,
        heroine: Heroine,
        firstSession: LanguageModelSession,
        onPartial: (String) -> Void
    ) async throws -> String {
        var session = firstSession
        var attempt = 0
        while true {
            var shown = ""
            do {
                let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.8))
                for try await snapshot in stream {
                    let text = GeneratedTextCleaner.line(snapshot.content)
                    if !text.isEmpty, text != shown {
                        shown = text
                        onPartial(text)
                    }
                }
                guard !shown.isEmpty else { throw CancellationError() }
                return shown
            } catch let error as LanguageModelError {
                guard case .guardrailViolation = error, shown.isEmpty, attempt < Self.guardrailRetryLimit else { throw error }
                attempt += 1
                session = makeLineSession(for: heroine)
            }
        }
    }

    // MARK: - 2. 選択肢

    /// 生成や整形に失敗したら空配列を返し、呼び出し側の定型の選択肢に任せる
    private func choices(heroine: Heroine, directive: SceneDirective, heroineLine: String) async -> [ChoiceOption] {
        let tones = ChoiceTone.plannedSet()
        let session = LanguageModelSession(model: dialogueModel, instructions: PromptBuilder.choiceInstructions)
        guard let response = try? await session.respond(
            to: PromptBuilder.choicePrompt(heroine: heroine, directive: directive, heroineLine: heroineLine, tones: tones),
            options: GenerationOptions(temperature: 0.8)
        ) else { return [] }

        let texts = GeneratedTextCleaner.choices(response.content, count: Self.choiceCount)
        guard texts.count == Self.choiceCount else { return [] }

        var options: [ChoiceOption] = []
        for (tone, text) in zip(tones, texts) {
            let delta = await reaction(heroine: heroine, heroineLine: heroineLine, choice: text)
            options.append(ChoiceOption(text: text, tone: tone, suggestedDelta: delta))
        }
        return options
    }

    // MARK: - 3. 判定

    private func emotion(for line: String) async -> Emotion {
        let session = LanguageModelSession(model: taggingModel)
        let response = try? await session.respond(to: PromptBuilder.emotionPrompt(line: line), generating: EmotionTag.self)
        return response?.content.emotion ?? .normal
    }

    private func reaction(heroine: Heroine, heroineLine: String, choice: String) async -> Int {
        let session = LanguageModelSession(model: taggingModel)
        let response = try? await session.respond(
            to: PromptBuilder.reactionPrompt(heroine: heroine, heroineLine: heroineLine, choice: choice),
            generating: ReactionScore.self
        )
        return response?.content.delta ?? 0
    }

    // MARK: - Session

    private func makeLineSession(for heroine: Heroine) -> LanguageModelSession {
        LanguageModelSession(model: dialogueModel, instructions: PromptBuilder.instructions(for: heroine))
    }

    /// prewarm 済みのセッションがあれば使い、なければ新しく作る。
    /// 1ターン1セッションにして、コンテキストが溢れないようにしている。
    private func takeSession(for heroine: Heroine) -> LanguageModelSession {
        defer { prewarm(for: heroine) }
        if let warmed = warmedSession, warmed.heroineID == heroine.id {
            return warmed.session
        }
        return makeLineSession(for: heroine)
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
