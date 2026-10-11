import Foundation
import Testing
@testable import GyaruGame

/// モック LLM で、ヒロイン選択 → 選択肢 → 好感度反映 → 締めのターン → 次のシーン の流れを通しで確認する
@MainActor
struct GameViewModelTests {
    private func makeGame() throws -> GameViewModel {
        let container = try SaveRepository.makeContainer(inMemory: true)
        return GameViewModel(
            content: try GameContent.loadFromBundle(),
            repository: SaveRepository(container: container),
            backend: .mock,
            mockGenerator: MockDialogueGenerator(characterDelay: .zero)
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private func readUntilChoices(_ game: GameViewModel) async throws {
        try await waitUntil { !game.isGenerating }
        for _ in 0..<20 where !game.showsChoices {
            game.advance()
        }
        #expect(game.showsChoices)
    }

    @Test func playsThroughFirstScene() async throws {
        let game = try makeGame()
        game.showHeroineSelect()
        #expect(game.screen == .heroineSelect)
        game.newGame(heroineID: "hiyori")
        #expect(game.screen == .playing)
        #expect(game.heroine?.id == "hiyori")
        #expect(game.currentLine?.speaker == nil) // 最初は地の文

        try await readUntilChoices(game)
        #expect(game.choices.count == 3)

        // kind: 基準+2 相性0 LLM+1（提案+2 を ±1 に丸める）→ +3
        game.choose(game.choices[0])
        #expect(game.currentAffection == 3)
        #expect(game.progress.turnInScene == 1)

        for _ in 0..<2 {
            try await readUntilChoices(game)
            game.choose(game.choices[0])
        }

        // 締めのターンは選択肢が出ない
        try await waitUntil { !game.isGenerating }
        #expect(game.choices.isEmpty)

        // 次のシーンも選んだヒロインのまま（第2章の屋上テラス）
        for _ in 0..<20 where game.directive?.scene.id == "c1_hiyori" {
            game.advance()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(game.directive?.scene.id == "c2_hiyori")
        #expect(game.heroine?.id == "hiyori")
        #expect(game.progress.chapterIndex == 1)
        #expect(game.progress.affection == 9)
    }
}
