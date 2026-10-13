import Foundation
import Testing
@testable import GyaruGame

/// スタブの判定役で、共通の導入 → 山札のイベント → 分岐 → エンディング の流れを通しで確認する
@MainActor
struct GameViewModelTests {
    private func makeGame(judge: StubJudge = StubJudge(), seed: UInt64 = 1) throws -> GameViewModel {
        let container = try SaveRepository.makeContainer(inMemory: true)
        return GameViewModel(
            content: try GameContent.loadFromBundle(),
            repository: SaveRepository(container: container),
            judge: judge,
            seed: seed
        )
    }

    /// 選択肢が出たら最初のものを選び、それ以外は読み進める
    private func play(_ game: GameViewModel, until done: () -> Bool) async throws {
        for _ in 0..<3000 where !done() {
            if game.showsChoices {
                game.choose(game.choices[0])
            } else {
                game.advance()
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func everyStorySceneHasScript() throws {
        let content = try GameContent.loadFromBundle()
        let story = content.story
        let ids = story.prologue + story.deck + story.routes.flatMap { $0.scenes + ($0.endingScenes ?? [:]).values.sorted() }
        for id in ids {
            #expect(story.scene(id: id) != nil, "\(id) が story.json の scenes にない")
            #expect(content.script(for: id) != nil, "\(id) のシナリオがない")
        }
    }

    /// 山札は引いた順に関係なく月の順に並ぶので、ルートに入ってから月が逆戻りしないよう、ルートの最初のシーンは山札のいちばん遅い月以降にする
    @Test func routesNeverGoBackInTime() throws {
        let story = try GameContent.loadFromBundle().story
        let deckMonths = story.deck.compactMap { story.scene(id: $0)?.month }
        let latestDeckMonth = try #require(deckMonths.max())
        for route in story.routes {
            let months = (route.scenes + (route.endingScenes ?? [:]).values.sorted()).compactMap { story.scene(id: $0)?.month }
            #expect(months.first.map { $0 >= latestDeckMonth } ?? true, "\(route.axis) のルートが山札より前の月から始まる")
            #expect(months == months.sorted(), "\(route.axis) のルートの中で月が逆戻りする")
        }
    }

    @Test func choicesComeFromScriptAndReactionFollows() async throws {
        let judge = StubJudge()
        let game = try makeGame(judge: judge)
        game.newGame()
        #expect(game.screen == .playing)
        #expect(game.scene?.id == "prologue_office")

        try await play(game) { game.showsChoices }
        #expect(game.choices.count == ScriptChoice.shownCount)
        let picked = game.choices[0]
        game.choose(picked)
        #expect(game.currentLine?.speaker == GameConstants.playerName)
        #expect(game.currentLine?.text == picked.text)

        // 次の行は、人が書いた反応
        game.advance()
        #expect(game.currentLine?.speaker == game.heroine.name)

        // 判定は裏で行われ、気持ちに足される
        for _ in 0..<200 where game.progress.feelings == Feelings() { try await Task.sleep(for: .milliseconds(5)) }
        #expect(game.progress.feelings == Feelings(tokimeki: 1, trust: 0, nori: 2))
        // 動いた軸だけが、表示用の結果になる（信頼は 0 なので出さない）
        #expect(game.feelingFeedback?.changes == [.init(axis: .tokimeki, delta: 1), .init(axis: .nori, delta: 2)])
        #expect(judge.requests.first?.playerLine == picked.text)
        #expect(judge.requests.first?.scene.id == "prologue_office")
    }

    /// ひよりはシーンの頭では画面にいない。声だけが先に聞こえ、enter の次の行で出てきて、exit でいなくなる
    @Test func heroineEntersAndExitsAsScripted() async throws {
        let game = try makeGame()
        game.newGame()
        #expect(game.scene?.id == "prologue_office")
        #expect(!game.isHeroineOnStage)

        try await play(game) { game.currentLine?.speaker == game.heroine.name }
        #expect(game.currentLine?.text == "……センパイ、さっきからみんなのキーボードばっか見てません？")
        #expect(!game.isHeroineOnStage)

        game.advance()
        #expect(game.currentLine?.text.hasPrefix("隣の席から") == true)
        #expect(game.isHeroineOnStage)

        try await play(game) { game.currentLine?.text.hasPrefix("その夜、帰りの電車で") == true }
        #expect(!game.isHeroineOnStage)
    }

    @Test func unreadableJudgmentChangesNothing() async throws {
        let game = try makeGame(judge: StubJudge { _ in "ひよりは笑った" })
        game.newGame()
        try await play(game) { game.showsChoices }
        game.choose(game.choices[0])
        try await play(game) { game.scene?.id != "prologue_office" }
        #expect(game.progress.feelings == Feelings())
        // どの軸も動かなかったときは、何も表示しない
        #expect(game.feelingFeedback == nil)
    }

    /// ときめきだけが上がり続けると、山札のあとでときめきのルートに入り、Good エンディングになる
    @Test func playsWholeGameIntoRouteAndEnding() async throws {
        let game = try makeGame(judge: StubJudge { _ in "ときめき +3 / 信頼 0 / ノリ 0" })
        game.newGame()
        var visited: [String] = []
        try await play(game) {
            if let id = game.scene?.id, visited.last != id { visited.append(id) }
            if case .ending = game.screen { return true }
            return false
        }

        let story = game.content.story
        #expect(Array(visited.prefix(2)) == story.prologue)
        #expect(game.progress.route != nil)
        guard case .ending(let ending) = game.screen else {
            Issue.record("エンディングに着いていない")
            return
        }
        #expect(ending.route == game.progress.route)
        // ルートのシーンのあとに、決まった結末のシーンが流れてからエンディングになる
        let route = try #require(story.route(for: ending.route))
        let endingScene = try #require(route.endingScenes?[ending.kind.rawValue])
        #expect(Array(visited.suffix(route.scenes.count + 1)) == route.scenes + [endingScene])
        if ending.route == .tokimeki {
            #expect(ending.kind == .good)
        }
        #expect(!game.hasContinuableSave)
    }

    @Test func continueRestartsSceneWithoutDuplicatingLogs() async throws {
        let container = try SaveRepository.makeContainer(inMemory: true)
        let repository = SaveRepository(container: container)
        let content = try GameContent.loadFromBundle()
        let game = GameViewModel(content: content, repository: repository, judge: StubJudge(), seed: 3)
        game.newGame()
        try await play(game) { game.scene?.id == "prologue_ikkakuya" }
        for _ in 0..<8 { game.advance() }
        let sceneID = "prologue_ikkakuya"
        let earlierLogs = game.backlog.filter { $0.sceneID != sceneID }.count
        #expect(game.backlog.contains { $0.sceneID == sceneID })
        game.returnToTitle()
        #expect(game.hasContinuableSave)

        // シーンの頭からやり直し、途中まで読んでいた分のログは残らない（地の文はログに残さない）
        game.continueGame()
        #expect(game.scene?.id == sceneID)
        #expect(game.cursor == 0)
        #expect(game.backlog.filter { $0.sceneID != sceneID }.count == earlierLogs)
        #expect(game.backlog.filter { $0.sceneID == sceneID }.count == (game.currentLine?.speaker == nil ? 0 : 1))
    }
}
