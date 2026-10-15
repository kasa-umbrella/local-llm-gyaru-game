import Foundation
import Testing
@testable import GyaruGame

/// 自由入力（自分の言葉で伝える）の判定の読み取り、入力の整形、セリフ集、進行を確認する
struct FreeInputParsingTests {
    @Test func readsKindAndAxes() throws {
        let judgment = try #require(JudgmentParser.parseFreeInput("反応: 照れ / ときめき +2 / 信頼 0 / ノリ +1"))
        #expect(judgment.kind == .flutter)
        #expect(judgment.delta == Feelings(tokimeki: 2, trust: 0, nori: 1))
    }

    @Test func readsFullWidthAndThinkingTags() throws {
        let raw = "<think>反応: 爆笑 ときめき +3</think>\n反応：安心／ときめき　＋１／信頼　＋３／ノリ　０"
        let judgment = try #require(JudgmentParser.parseFreeInput(raw))
        #expect(judgment.kind == .relief)
        #expect(judgment.delta == Feelings(tokimeki: 1, trust: 3, nori: 0))
    }

    /// 反応と食い違う判定（ムッとしたのにときめきが上がる）は、その反応で上げられる上限までに抑える
    @Test func capsGainsByKind() throws {
        let upset = try #require(JudgmentParser.parseFreeInput("反応: ムッとする / ときめき +3 / 信頼 -2 / ノリ +1"))
        #expect(upset.delta == Feelings(tokimeki: 0, trust: -2, nori: 0))

        let puzzled = try #require(JudgmentParser.parseFreeInput("反応: 困惑 / ときめき +3 / 信頼 0 / ノリ +2"))
        #expect(puzzled.delta == Feelings(tokimeki: 1, trust: 0, nori: 1))

        let plain = try #require(JudgmentParser.parseFreeInput("反応: ふつう / ときめき 0 / 信頼 +3 / ノリ 0"))
        #expect(plain.delta == Feelings(tokimeki: 0, trust: 1, nori: 0))
    }

    @Test func rejectsIncompleteOutput() {
        // 反応の種類がない・知らない種類・軸が1つも読めない
        #expect(JudgmentParser.parseFreeInput("ときめき +1 / 信頼 0 / ノリ +2") == nil)
        #expect(JudgmentParser.parseFreeInput("反応: 大笑い / ときめき +1 / 信頼 0 / ノリ +2") == nil)
        #expect(JudgmentParser.parseFreeInput("反応: 照れ") == nil)
        #expect(JudgmentParser.parseFreeInput("") == nil)
    }

    /// 最後の軸を書き忘れても、書かれた分は読む（書かれなかった軸は動かなかったことにする）
    @Test func treatsMissingAxesAsUnchanged() throws {
        let judgment = try #require(JudgmentParser.parseFreeInput("反応：安心 / ときめき +2 / 信頼 +1"))
        #expect(judgment.kind == .relief)
        #expect(judgment.delta == Feelings(tokimeki: 2, trust: 1, nori: 0))
        // 選択肢の判定は、3つそろわなければ読めない
        #expect(JudgmentParser.parse("ときめき +2 / 信頼 +1") == nil)
    }

    /// 選択肢の判定は、頭に反応の種類が付いていても同じように読める
    @Test func choiceJudgmentIgnoresKindPrefix() {
        #expect(JudgmentParser.parse("反応: 照れ / ときめき +1 / 信頼 0 / ノリ +2") == Feelings(tokimeki: 1, trust: 0, nori: 2))
    }

    @Test func kindLabelsDoNotCollideWithAxisLabels() {
        let axisLabels = Axis.allCases.map(\.label)
        for kind in ReplyKind.allCases {
            #expect(!axisLabels.contains { kind.label.contains($0) || $0.contains(kind.label) }, "\(kind.label) が軸の名前と重なる")
        }
        #expect(Set(ReplyKind.allCases.map(\.label)).count == ReplyKind.allCases.count)
    }
}

struct FreeInputTextTests {
    @Test func sanitizesInput() {
        #expect(FreeInput.sanitized("  いつもありがとな  ") == "いつもありがとな")
        #expect(FreeInput.sanitized("一行目\n二行目") == "一行目 二行目")
        #expect(FreeInput.sanitized("　全角の空白　") == "全角の空白")
        #expect(FreeInput.sanitized("") == nil)
        #expect(FreeInput.sanitized("   \n \u{3000} ") == nil)
    }

    @Test func cutsLongInput() throws {
        let long = String(repeating: "あ", count: FreeInput.characterLimit + 25)
        let result = try #require(FreeInput.sanitized(long))
        #expect(result.count == FreeInput.characterLimit)
    }
}

struct FreeRepliesTests {
    @Test func everyKindHasEnoughVariedReplies() throws {
        let replies = try GameContent.loadFromBundle().freeReplies
        for kind in ReplyKind.allCases {
            let candidates = replies.candidates(for: kind)
            #expect(candidates.count >= 3, "\(kind.label) の反応が少ない")
            #expect(Set(candidates.map(\.text)).count == candidates.count, "\(kind.label) の反応に重複がある")
            #expect(candidates.allSatisfy { !$0.text.isEmpty }, "\(kind.label) に空の反応がある")
        }
        // 知らないキーが混ざっていたら気づけるように
        #expect(Set(replies.replies.keys) == Set(ReplyKind.allCases.map(\.rawValue)))
    }

    /// 反応は気分を沈める種類のときだけ怒り・悲しみの表情にする
    @Test func negativeExpressionsOnlyForUpset() throws {
        let replies = try GameContent.loadFromBundle().freeReplies
        for kind in ReplyKind.allCases where kind != .upset {
            let candidates = replies.candidates(for: kind)
            #expect(candidates.allSatisfy { $0.emotion != .angry && $0.emotion != .sad }, "\(kind.label) に怒り・悲しみの表情がある")
        }
    }

    @Test func picksUnusedRepliesFirst() throws {
        let replies = try GameContent.loadFromBundle().freeReplies
        var generator = SeededGenerator(seed: 7)
        let all = replies.candidates(for: .laugh)
        var used: Set<String> = []
        for _ in all {
            let reply = replies.pick(for: .laugh, avoiding: used, using: &generator)
            #expect(!used.contains(reply.text))
            used.insert(reply.text)
        }
        #expect(used == Set(all.map(\.text)))
        // 使い切ったら、その種類の全部から選び直す
        let again = replies.pick(for: .laugh, avoiding: used, using: &generator)
        #expect(used.contains(again.text))
    }

    @Test func fallsBackWhenKindIsMissing() {
        var generator = SeededGenerator(seed: 1)
        let reply = FreeReplies(replies: [:]).pick(for: .flutter, avoiding: [], using: &generator)
        #expect(reply.text == FreeReplies.lastResort.text)
    }
}

struct FreeInputScriptTests {
    private func choiceBeats(in script: SceneScript) -> [Bool] {
        script.beats.compactMap {
            if case .choice(_, let allowsFreeInput) = $0 { allowsFreeInput } else { nil }
        }
    }

    /// 告白の返事の直前で止める最後の選択肢は、人が書いた反応だけにする
    @Test func routeFinalesDoNotAllowFreeInput() throws {
        let content = try GameContent.loadFromBundle()
        for route in content.story.routes {
            let lastScene = try #require(route.scenes.last)
            let flags = choiceBeats(in: try #require(content.script(for: lastScene)))
            #expect(flags.last == false, "\(lastScene) の最後の選択肢で自由入力ができてしまう")
        }
    }

    @Test func otherChoicesAllowFreeInput() throws {
        let content = try GameContent.loadFromBundle()
        let finales = Set(content.story.routes.compactMap(\.scenes.last))
        for (id, script) in content.scripts {
            let flags = choiceBeats(in: script)
            let expected = finales.contains(id) ? Array(repeating: true, count: flags.count - 1) + [false] : Array(repeating: true, count: flags.count)
            #expect(flags == expected, "\(id) の自由入力の設定が想定とちがう")
        }
    }

    @Test func freeInputFlagSurvivesEncoding() throws {
        let choice = ScriptChoice(text: "やあ", reaction: ScriptReaction(text: "どうも", emotion: .smile))
        for flag in [true, false] {
            let data = try JSONEncoder().encode(ScriptBeat.choice([choice], allowsFreeInput: flag))
            guard case .choice(let options, let decoded) = try JSONDecoder().decode(ScriptBeat.self, from: data) else {
                Issue.record("選択肢として読めない")
                return
            }
            #expect(options.count == 1)
            #expect(decoded == flag)
        }
        // 書かなければオフ
        let plain = Data(#"{"type":"choice","options":[{"text":"やあ","reaction":{"text":"どうも","emotion":"smile"}}]}"#.utf8)
        guard case .choice(_, let decoded) = try JSONDecoder().decode(ScriptBeat.self, from: plain) else {
            Issue.record("選択肢として読めない")
            return
        }
        #expect(decoded == false)
    }
}

/// 判定が長引いても、上限時間で相づちにして先へ進む
@MainActor
struct FreeInputTimeoutTests {
    private static let request: JudgeRequest = {
        let content = try! GameContent.loadFromBundle()
        return JudgeRequest(
            heroine: content.heroine, scene: content.story.scenes[0], mood: .calm, feelings: Feelings(),
            recentLines: [], playerLine: "お疲れさま", reaction: nil
        )
    }()

    @Test func givesUpWhenJudgmentIsTooSlow() async {
        let judge = SlowJudge(delay: .seconds(5)) { _ in "反応: 照れ / ときめき +2 / 信頼 0 / ノリ +1" }
        let start = ContinuousClock.now
        let judgment = await judge.judgedFreeInput(Self.request, timeout: .milliseconds(150))
        #expect(judgment == .fallback)
        #expect(ContinuousClock.now - start < .seconds(2), "上限時間を過ぎても待ち続けている")
    }

    @Test func usesJudgmentThatArrivesInTime() async {
        let judge = SlowJudge(delay: .milliseconds(30)) { _ in "反応: 照れ / ときめき +2 / 信頼 0 / ノリ +1" }
        let judgment = await judge.judgedFreeInput(Self.request, timeout: .seconds(5))
        #expect(judgment.kind == .flutter)
        #expect(judgment.delta == Feelings(tokimeki: 2, trust: 0, nori: 1))
    }
}

/// 判定に時間がかかる（本物のLLMのような）判定役。返事を待っている間の画面の動きを確認する
private final class SlowJudge: FeelingJudging {
    private let delay: Duration
    private let respond: (JudgeRequest) -> String
    private(set) var requests: [JudgeRequest] = []

    init(delay: Duration = .milliseconds(120), _ respond: @escaping (JudgeRequest) -> String) {
        self.delay = delay
        self.respond = respond
    }

    func prewarm() {}

    func judge(_ request: JudgeRequest) async throws -> String {
        requests.append(request)
        try await Task.sleep(for: delay)
        return respond(request)
    }
}

@MainActor
struct FreeInputGameTests {
    private static let flutter = "反応: 照れ / ときめき +2 / 信頼 0 / ノリ +1"

    private func makeGame(judge: FeelingJudging, content: GameContent? = nil, seed: UInt64 = 1) throws -> GameViewModel {
        let container = try SaveRepository.makeContainer(inMemory: true)
        return GameViewModel(
            content: try content ?? GameContent.loadFromBundle(),
            repository: SaveRepository(container: container),
            judge: judge,
            seed: seed
        )
    }

    /// 選択肢が出るまで読み進める
    private func playUntilChoices(_ game: GameViewModel) async throws {
        for _ in 0..<3000 where !game.showsChoices {
            game.advance()
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(game.showsChoices)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func freeInputIsOfferedWithChoices() async throws {
        let game = try makeGame(judge: StubJudge())
        game.newGame()
        #expect(!game.allowsFreeInput)
        try await playUntilChoices(game)
        #expect(game.allowsFreeInput)
    }

    /// 入力した一言がそのまま主人公のセリフになり、判定が選んだ種類の反応が、人の書いたセリフ集から出る
    @Test func freeInputBecomesPlayerLineAndWrittenReaction() async throws {
        let judge = StubJudge { _ in Self.flutter }
        let game = try makeGame(judge: judge)
        game.newGame()
        try await playUntilChoices(game)

        game.submitFreeInput("  いつも助かってる、ありがとな \n")
        #expect(game.currentLine?.speaker == GameConstants.playerName)
        #expect(game.currentLine?.text == "いつも助かってる、ありがとな")
        #expect(game.choices.isEmpty)
        #expect(!game.allowsFreeInput)

        try await waitUntil { !game.isAwaitingReaction }
        #expect(!game.isAwaitingReaction)
        // 反応はカーソルを動かさずに積まれ、読み進めると出る
        #expect(game.currentLine?.speaker == GameConstants.playerName)
        game.advance()
        let reaction = try #require(game.currentLine)
        #expect(reaction.speaker == game.heroine.name)
        let written = game.content.freeReplies.candidates(for: .flutter)
        #expect(written.contains { $0.text == reaction.text && $0.emotion == reaction.emotion })

        // 気持ちが動き、判定役には「まだ反応がない」依頼が渡る
        #expect(game.progress.feelings == Feelings(tokimeki: 2, trust: 0, nori: 1))
        #expect(game.feelingFeedback?.changes == [.init(axis: .tokimeki, delta: 2), .init(axis: .nori, delta: 1)])
        let request = try #require(judge.requests.first)
        #expect(request.isFreeInput)
        #expect(request.playerLine == "いつも助かってる、ありがとな")
        #expect(request.scene.id == "prologue_office")

        // バックログには、入力した一言と反応が残る
        let logs = game.backlog.map(\.text)
        #expect(logs.contains("いつも助かってる、ありがとな"))
        #expect(logs.contains(reaction.text))
    }

    @Test func waitsForReactionBeforeAdvancing() async throws {
        let game = try makeGame(judge: SlowJudge { _ in Self.flutter })
        game.newGame()
        try await playUntilChoices(game)
        game.submitFreeInput("お疲れさま")

        // 判定役が答えるまでは、先へ進めない
        #expect(game.isAwaitingReaction)
        #expect(!game.canAdvance)
        let cursor = game.cursor
        game.advance()
        #expect(game.cursor == cursor)
        #expect(game.currentLine?.text == "お疲れさま")

        try await waitUntil { !game.isAwaitingReaction }
        #expect(game.canAdvance)
        game.advance()
        #expect(game.currentLine?.speaker == game.heroine.name)
    }

    @Test func unreadableJudgmentFallsBackToPlainReply() async throws {
        let judge = StubJudge { _ in "ひよりは笑った" }
        let game = try makeGame(judge: judge)
        game.newGame()
        try await playUntilChoices(game)
        game.submitFreeInput("今日、いい天気だな")
        try await waitUntil { !game.isAwaitingReaction }

        game.advance()
        let reaction = try #require(game.currentLine)
        #expect(game.content.freeReplies.candidates(for: .plain).contains { $0.text == reaction.text })
        #expect(game.progress.feelings == Feelings())
        #expect(game.feelingFeedback == nil)
        // 読み取れなければ1回だけやり直す
        #expect(judge.requests.count == 2)
    }

    @Test func ignoresBlankInput() async throws {
        let judge = StubJudge { _ in Self.flutter }
        let game = try makeGame(judge: judge)
        game.newGame()
        try await playUntilChoices(game)

        game.submitFreeInput("   \n  ")
        #expect(game.showsChoices)
        #expect(!game.isAwaitingReaction)
        #expect(judge.requests.isEmpty)
    }

    /// シナリオが自由入力を許していない選択肢では、入力しても何も起きない
    @Test func ignoresInputWhereScriptDoesNotAllowIt() async throws {
        var content = try GameContent.loadFromBundle()
        var scripts = content.scripts
        let original = try #require(scripts["prologue_office"])
        scripts["prologue_office"] = SceneScript(sceneID: original.sceneID, beats: original.beats.map {
            if case .choice(let options, _) = $0 { .choice(options, allowsFreeInput: false) } else { $0 }
        })
        content = GameContent(heroine: content.heroine, story: content.story, scripts: scripts, freeReplies: content.freeReplies)

        let judge = StubJudge { _ in Self.flutter }
        let game = try makeGame(judge: judge, content: content)
        game.newGame()
        try await playUntilChoices(game)
        #expect(!game.allowsFreeInput)

        game.submitFreeInput("ひよりのこと、すごいと思ってる")
        #expect(game.showsChoices)
        #expect(game.choices.count == ScriptChoice.shownCount)
        #expect(judge.requests.isEmpty)
    }

    @Test func returningToTitleCancelsPendingReaction() async throws {
        let game = try makeGame(judge: SlowJudge(delay: .milliseconds(200)) { _ in Self.flutter })
        game.newGame()
        try await playUntilChoices(game)
        game.submitFreeInput("お疲れさま")
        #expect(game.isAwaitingReaction)

        game.returnToTitle()
        #expect(!game.isAwaitingReaction)
        try await Task.sleep(for: .milliseconds(400))
        // 遅れて返ってきた判定が、タイトルに戻ったあとの状態を汚さない
        #expect(game.script.isEmpty)
        #expect(game.progress.feelings == Feelings())
    }

    /// 一周を通して、自由入力と選択肢を混ぜて進めてもエンディングまで届く
    @Test func playsWholeGameMixingFreeInputAndChoices() async throws {
        let game = try makeGame(judge: StubJudge { request in
            request.isFreeInput ? Self.flutter : "ときめき +3 / 信頼 0 / ノリ 0"
        })
        game.newGame()
        var freeInputs = 0
        for step in 0..<6000 {
            if case .ending = game.screen { break }
            if game.showsChoices {
                if game.allowsFreeInput, step % 2 == 0 {
                    game.submitFreeInput("ひよりと話してると楽しい")
                    freeInputs += 1
                } else {
                    game.choose(game.choices[0])
                }
            } else {
                game.advance()
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard case .ending = game.screen else {
            Issue.record("エンディングに着いていない")
            return
        }
        #expect(freeInputs > 0)
    }
}
