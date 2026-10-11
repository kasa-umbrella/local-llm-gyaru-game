import FoundationModels
import Testing
@testable import GyaruGame

/// 実機のオンデバイスモデルで各シーンのターンを生成できるかの確認。
/// Apple Intelligence が使えない環境では自動でスキップされる。
@MainActor
@Suite(.enabled(if: SystemLanguageModel.default.availability == .available), .serialized)
struct FoundationModelSmokeTests {
    @Test(arguments: [
        ("hiyori", 0, nil), ("mio", 0, nil), ("ruka", 0, nil),
        ("hiyori", 1, "うまそう、いただきます"), ("mio", 1, "最後まで読んだよ、面白かった"), ("ruka", 1, "今日はとことん付き合うよ"),
    ] as [(String, Int, String?)])
    func generatesTurn(heroineID: String, chapterIndex: Int, lastChoice: String?) async throws {
        let content = try GameContent.loadFromBundle()
        let director = StoryDirector(chapters: content.chapters)
        let progress = GameProgress(heroineID: heroineID, chapterIndex: chapterIndex, turnInScene: lastChoice == nil ? 0 : 1)
        let directive = try #require(director.directive(for: progress))
        let heroine = try #require(content.heroine(id: directive.heroineID))
        let affection = lastChoice == nil ? 0 : 35

        let request = TurnRequest(
            heroine: heroine, directive: directive, affection: affection,
            summaries: [], recentLog: [],
            lore: LoreRetriever(entries: content.lore).retrieve(
                heroineID: heroine.id, sceneTags: directive.scene.tags, recentText: lastChoice ?? ""
            ),
            lastChoice: lastChoice
        )

        var final: TurnDraft?
        for try await draft in FoundationModelDialogueGenerator().streamTurn(request) where draft.isFinal {
            final = draft
        }
        let turn = try #require(final)
        #expect(!turn.lines.isEmpty)
        #expect(turn.lines.allSatisfy { !$0.text.isEmpty })
        #expect(turn.choices.count == FoundationModelDialogueGenerator.choiceCount)

        print("---- \(heroine.name) / \(directive.scene.location) ----")
        turn.lines.forEach { print("[\($0.emotion)] \($0.text)") }
        turn.choices.forEach { print("  > \($0.text) (\($0.tone), \($0.suggestedDelta))") }
    }
}
