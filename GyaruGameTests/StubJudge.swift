import Foundation

/// LLM なしで UI と進行ロジックを確認するためのモック。
/// Apple Intelligence が使えない環境や、起動引数 `-useMockLLM` で使う。
final class MockDialogueGenerator: DialogueGenerating {
    private let characterDelay: Duration

    init(characterDelay: Duration = .milliseconds(25)) {
        self.characterDelay = characterDelay
    }

    func prewarm(for heroine: Heroine) {}

    func streamTurn(_ request: TurnRequest) -> AsyncThrowingStream<TurnDraft, Error> {
        let heroine = request.heroine
        let finalLines = [
            DialogueLine(
                speaker: heroine.name,
                text: request.lastChoice.map { "「\($0)」って……ふふ、\(heroine.callsPlayer)らしいね。" }
                    ?? heroine.sampleLines.randomElement() ?? "……",
                emotion: request.lastChoice == nil ? .normal : .smile
            ),
            DialogueLine(
                speaker: heroine.name,
                text: heroine.sampleLines.randomElement() ?? "……",
                emotion: Emotion.allCases.randomElement() ?? .normal
            ),
        ]
        let choices = [
            ChoiceOption(text: "優しく笑いかける", tone: .kind, suggestedDelta: 2),
            ChoiceOption(text: "ちょっとからかってみる", tone: .teasing, suggestedDelta: 1),
            ChoiceOption(text: "そっけなく返す", tone: .cool, suggestedDelta: -1),
        ]
        let delay = characterDelay

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var streamed: [DialogueLine] = []
                    for line in finalLines {
                        var partial = line
                        partial.text = ""
                        streamed.append(partial)
                        for character in line.text {
                            try await Task.sleep(for: delay)
                            streamed[streamed.count - 1].text.append(character)
                            continuation.yield(TurnDraft(lines: streamed, choices: [], isFinal: false))
                        }
                    }
                    continuation.yield(TurnDraft(lines: finalLines, choices: choices, isFinal: true))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func summarize(_ request: SummaryRequest) async throws -> String {
        "第\(request.directive.chapterNumber)章、\(request.directive.scene.location)で\(request.heroine.name)と過ごした。"
    }
}
