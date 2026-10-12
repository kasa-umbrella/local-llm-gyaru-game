import Testing
@testable import GyaruGame

@MainActor
struct StoryDirectorTests {
    private static func scene(_ id: String, month: Int) -> SceneDefinition {
        SceneDefinition(id: id, location: id, background: "", month: month)
    }

    private static func route(_ axis: Axis, scenes: [String]) -> Route {
        Route(axis: axis, title: axis.label, scenes: scenes, endings: ["good": "good", "normal": "normal"])
    }

    private let director = StoryDirector(story: Story(
        prologue: ["p1", "p2"],
        deck: ["e_jul", "e_may", "e_jun", "e_aug"],
        deckDrawCount: 3,
        routes: [route(.tokimeki, scenes: ["r_t"]), route(.trust, scenes: []), route(.nori, scenes: ["r_n1", "r_n2"])],
        scenes: [
            scene("p1", month: 4), scene("p2", month: 5),
            scene("e_may", month: 5), scene("e_jun", month: 6), scene("e_jul", month: 7), scene("e_aug", month: 8),
            scene("r_t", month: 9), scene("r_n1", month: 9), scene("r_n2", month: 10),
        ]
    ))

    @Test(arguments: [UInt64(1), 2, 3, 42])
    func drawsEventsInMonthOrderAfterPrologue(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        let progress = director.newGame(using: &random)
        #expect(progress.sceneQueue.prefix(2) == ["p1", "p2"])
        let events = progress.sceneQueue.dropFirst(2)
        #expect(events.count == 3)
        let months = events.compactMap { director.story.scene(id: $0)?.month }
        #expect(months == months.sorted())
    }

    @Test func sameSeedGivesSameDeck() {
        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        #expect(director.newGame(using: &a) == director.newGame(using: &b))
    }

    @Test func entersRouteAfterLastEvent() {
        var random = SeededGenerator(seed: 1)
        let progress = GameProgress(sceneQueue: ["p1", "e_may"], sceneIndex: 1, feelings: Feelings(tokimeki: 0, trust: 0, nori: 90))
        // ノリが圧倒的に高い（重み 95 : 5 : 5）ので、たいていノリのルートに入る
        guard case .scene(let next) = director.nextStep(after: progress, using: &random) else {
            Issue.record("ルートのシーンに進んでいない")
            return
        }
        #expect(next.route == .nori)
        #expect(next.sceneQueue == ["p1", "e_may", "r_n1", "r_n2"])
        #expect(director.scene(for: next)?.id == "r_n1")
    }

    @Test func routeWithoutScenesGoesStraightToEnding() {
        var random = SeededGenerator(seed: 1)
        let progress = GameProgress(sceneQueue: ["p1"], feelings: Feelings(tokimeki: 0, trust: 90, nori: 0))
        #expect(director.nextStep(after: progress, using: &random) == .ending(Ending(kind: .good, route: .trust)))
    }

    @Test func weightsFavorStrongestAxisButKeepOthersPossible() {
        let weights = director.routeWeights(for: Feelings(tokimeki: 10, trust: 4, nori: 4))
        #expect(weights == [.tokimeki: 6 + StoryDirector.lotteryBase, .trust: StoryDirector.lotteryBase, .nori: StoryDirector.lotteryBase])
    }

    /// 選び方が同じでも、くじなので別のルートに転ぶことがある
    @Test func lotteryIsNotDeterministicAcrossSeeds() {
        let feelings = Feelings(tokimeki: 8, trust: 5, nori: 3)
        var drawn: Set<Axis> = []
        for seed in UInt64(0)..<200 {
            var random = SeededGenerator(seed: seed)
            drawn.insert(director.drawRoute(for: feelings, using: &random))
        }
        #expect(drawn == Set(Axis.allCases))
    }

    @Test(arguments: [(StoryDirector.goodEndingThreshold, Ending.Kind.good), (StoryDirector.goodEndingThreshold - 1, .normal)])
    func endingDependsOnRouteAxis(value: Int, expected: Ending.Kind) {
        let progress = GameProgress(sceneQueue: ["r_t"], route: .tokimeki, feelings: Feelings(tokimeki: value, trust: 99, nori: 99))
        #expect(director.ending(for: progress) == Ending(kind: expected, route: .tokimeki))
    }
}

@MainActor
struct FeelingsTests {
    @Test func addsAndClampsEachAxis() {
        let feelings = Feelings(tokimeki: 99, trust: 1, nori: 50)
        #expect(feelings.adding(Feelings(tokimeki: 3, trust: -2, nori: 1)) == Feelings(tokimeki: 100, trust: 0, nori: 51))
    }

    @Test func strongestPicksHighest() {
        #expect(Feelings(tokimeki: 1, trust: 5, nori: 3).strongest == .trust)
    }
}

@MainActor
struct JudgmentParserTests {
    @Test(arguments: [
        ("ときめき +1 / 信頼 0 / ノリ +2", Feelings(tokimeki: 1, trust: 0, nori: 2)),
        ("ときめき：－１　信頼：＋３　ノリ：０", Feelings(tokimeki: -1, trust: 3, nori: 0)),
        ("判定: ときめき+2、信頼-1、ノリ+1", Feelings(tokimeki: 2, trust: -1, nori: 1)),
        ("<think>うーん</think>ときめき 0 / 信頼 +1 / ノリ 0", Feelings(tokimeki: 0, trust: 1, nori: 0)),
    ])
    func readsJudgment(raw: String, expected: Feelings) {
        #expect(JudgmentParser.parse(raw) == expected)
    }

    @Test func clampsOutOfRangeValues() {
        #expect(JudgmentParser.parse("ときめき +9 / 信頼 -7 / ノリ +3") == Feelings(tokimeki: 3, trust: -2, nori: 3))
    }

    @Test(arguments: ["ときめき +1 / 信頼 0", "ひよりは嬉しそうだった", ""])
    func rejectsIncompleteJudgment(raw: String) {
        #expect(JudgmentParser.parse(raw) == nil)
    }
}
