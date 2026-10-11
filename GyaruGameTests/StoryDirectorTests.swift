import Testing
@testable import GyaruGame

@MainActor
struct StoryDirectorTests {
    private static func scene(_ id: String, cast: String, turns: Int = 2) -> SceneDefinition {
        SceneDefinition(id: id, cast: cast, location: "オフィス", background: "office", narration: "", tags: [], goal: "", turns: turns)
    }

    private let director = StoryDirector(chapters: [
        Chapter(id: 1, title: "出会い", scenes: [scene("h1", cast: "hiyori"), scene("m1", cast: "mio")]),
        Chapter(id: 2, title: "ミオだけ", scenes: [scene("m2", cast: "mio")]),
        Chapter(id: 3, title: "共通", scenes: [scene("x1", cast: SceneDefinition.selectedHeroineCast), scene("x2", cast: SceneDefinition.selectedHeroineCast)]),
    ])

    @Test func phaseFollowsTurnCount() {
        var progress = GameProgress(heroineID: "hiyori")
        #expect(director.directive(for: progress)?.phase == .intro)
        progress.turnInScene = 1
        #expect(director.directive(for: progress)?.phase == .development)
        progress.turnInScene = 2
        #expect(director.directive(for: progress)?.phase == .closing)
        #expect(director.isClosingTurn(progress))
    }

    @Test func onlySelectedHeroineScenesAreUsed() {
        let progress = GameProgress(heroineID: "mio")
        #expect(director.scene(for: progress)?.id == "m1")
        #expect(director.directive(for: progress)?.heroineID == "mio")
    }

    @Test func skipsChaptersWithoutTheHeroine() {
        let progress = GameProgress(heroineID: "hiyori", chapterIndex: 0, sceneIndex: 0, turnInScene: 2)
        #expect(director.nextStep(after: progress) == .scene(GameProgress(heroineID: "hiyori", chapterIndex: 2, sceneIndex: 0)))
    }

    @Test func sharedScenesUseSelectedHeroine() {
        let progress = GameProgress(heroineID: "ruka", chapterIndex: 2)
        #expect(director.scene(for: progress)?.id == "x1")
        #expect(director.directive(for: progress)?.heroineID == "ruka")
        #expect(director.nextStep(after: progress) == .scene(GameProgress(heroineID: "ruka", chapterIndex: 2, sceneIndex: 1)))
    }

    @Test(arguments: [(60, Ending.Kind.good), (40, .normal), (10, .bad)])
    func endingDependsOnAffection(affection: Int, expected: Ending.Kind) {
        let progress = GameProgress(heroineID: "ruka", chapterIndex: 2, sceneIndex: 1, turnInScene: 2, affection: affection)
        #expect(director.nextStep(after: progress) == .ending(Ending(kind: expected, heroineID: "ruka")))
    }
}

@MainActor
struct AffectionEngineTests {
    private let engine = AffectionEngine()
    private let heroine = Heroine(
        id: "ruka", name: "るか", role: "", tagline: "", firstPerson: "あたし", callsPlayer: "ユウキ", profile: "",
        speechRules: [], sampleLines: [], tonePreferences: ["teasing": 1, "rude": -2],
        fallbackLines: [], themeColor: "#FFFFFF"
    )

    @Test func combinesToneBasePreferenceAndLLMAdjustment() {
        // teasing: 基準+1 相性+1 LLM+1
        #expect(engine.delta(for: ChoiceOption(text: "", tone: .teasing, suggestedDelta: 2), heroine: heroine) == 3)
        // cool: 基準-1 相性0 LLM0
        #expect(engine.delta(for: ChoiceOption(text: "", tone: .cool, suggestedDelta: 0), heroine: heroine) == -1)
        // rude: 基準-3 相性-2 LLM-1 → 1ターンの下限 -5
        #expect(engine.delta(for: ChoiceOption(text: "", tone: .rude, suggestedDelta: -3), heroine: heroine) == -5)
    }

    @Test func llmSuggestionOnlyAdjustsByOne() {
        #expect(engine.delta(for: ChoiceOption(text: "", tone: .kind, suggestedDelta: 99), heroine: heroine) == 3)
        #expect(engine.delta(for: ChoiceOption(text: "", tone: .kind, suggestedDelta: -99), heroine: heroine) == 1)
    }

    @Test func clampsTotalAffection() {
        #expect(engine.apply(5, to: 98) == 100)
        #expect(engine.apply(-5, to: 2) == 0)
    }
}

@MainActor
struct LoreRetrieverTests {
    private let retriever = LoreRetriever(entries: [
        LoreEntry(id: "a", heroineID: "mio", tags: ["図書室"], keywords: ["紅茶"], text: "A"),
        LoreEntry(id: "b", heroineID: "mio", tags: ["本"], keywords: ["推理"], text: "B"),
        LoreEntry(id: "c", heroineID: "ruka", tags: ["図書室"], keywords: [], text: "C"),
    ])

    @Test func filtersByHeroineAndRanksByScore() {
        let result = retriever.retrieve(heroineID: "mio", sceneTags: ["本"], recentText: "その推理小説、紅茶を飲みながら読んだ")
        #expect(result.map(\.id) == ["b", "a"])
    }

    @Test func returnsNothingWithoutMatches() {
        #expect(retriever.retrieve(heroineID: "mio", sceneTags: ["屋上"], recentText: "").isEmpty)
    }
}
