import Foundation
import Testing
@testable import GyaruGame

/// シーンの途中で背景が切り替わること（昼のオフィス → 定時後の夜のオフィス、など）を確認する
@MainActor
struct BackgroundTests {
    @Test func everyBackgroundHasAsset() throws {
        let content = try GameContent.loadFromBundle()
        var names = Set(content.story.scenes.map(\.background))
        for script in content.scripts.values {
            for case .background(let name) in script.beats { names.insert(name) }
        }
        for name in names {
            #expect(AssetImage.named("bg_\(name)") != nil, "背景 bg_\(name) の画像がない")
        }
    }

    @Test func backgroundChangesInTheMiddleOfAScene() async throws {
        let container = try SaveRepository.makeContainer(inMemory: true)
        let game = GameViewModel(
            content: try GameContent.loadFromBundle(),
            repository: SaveRepository(container: container),
            judge: StubJudge(),
            seed: 1
        )
        game.newGame()
        #expect(game.scene?.id == "prologue_office")
        #expect(game.background == "office_building_day")

        // 最初の選択肢を選んで、定時後の場面へ進む
        var reachedEvening = false
        for _ in 0..<500 {
            if game.showsChoices {
                #expect(game.background == "office_building_day")
                game.choose(game.choices[0])
            } else {
                game.advance()
            }
            if game.currentLine?.text.hasPrefix("定時の十九時") == true {
                reachedEvening = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(reachedEvening)
        #expect(game.background == "office_building_night")
    }

    @Test func scriptBackgroundSurvivesEncoding() throws {
        let data = try JSONEncoder().encode(ScriptBeat.background("station_square_night"))
        guard case .background(let name) = try JSONDecoder().decode(ScriptBeat.self, from: data) else {
            Issue.record("背景として読めない")
            return
        }
        #expect(name == "station_square_night")
    }
}
