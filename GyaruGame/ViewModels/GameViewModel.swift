import Foundation
import FoundationModels
import Observation

/// ゲーム全体の状態遷移。
/// StoryDirector（監督）が決めた枠の中で、DialogueGenerating（演者）にセリフを生成させる。
@Observable
final class GameViewModel {
    enum Screen: Equatable {
        case title
        case heroineSelect
        case playing
        case ending(Ending)
    }

    /// プロンプトに入れる直近ログと要約の件数（コンテキスト長の節約）
    private static let recentLogLimit = 6
    private static let summaryLimit = 3

    let content: GameContent
    private let director: StoryDirector
    private let affectionEngine = AffectionEngine()
    private let retriever: LoreRetriever
    private let repository: SaveRepository
    private let foundationGenerator = FoundationModelDialogueGenerator()
    private let localGenerator = LocalLLMDialogueGenerator()
    private let mockGenerator: MockDialogueGenerator

    /// Apple のオンデバイスモデルが使えない場合のメッセージ（使えるなら nil）
    let appleModelUnavailableMessage: String?
    private(set) var localModelState: LocalModelState = .notDownloaded
    private var localModelTask: Task<Void, Never>?

    var backend: LLMBackend {
        didSet {
            guard backend != oldValue else { return }
            backend.save()
            if backend == .local { refreshLocalModel() }
        }
    }

    private(set) var screen: Screen = .title
    private(set) var progress = GameProgress(heroineID: "")
    private(set) var directive: SceneDirective?
    private(set) var heroine: Heroine?

    /// このシーンで表示した行（地の文・ヒロイン・主人公）
    private(set) var script: [DialogueLine] = []
    /// 表示中の行。script.count と等しいときは生成中の行（streamingLine）を表示する
    private(set) var cursor = 0
    private(set) var streamingLine: DialogueLine?
    private(set) var choices: [ChoiceOption] = []
    private(set) var isGenerating = false
    private(set) var isTransitioning = false
    private(set) var lastAffectionDelta: Int?
    private(set) var notice: String?

    private var slot: SaveSlot?
    private var generationTask: Task<Void, Never>?

    private var generator: DialogueGenerating {
        switch backend {
        case .local: localGenerator
        case .apple: foundationGenerator
        case .mock: mockGenerator
        }
    }

    init(
        content: GameContent,
        repository: SaveRepository,
        backend: LLMBackend? = nil,
        mockGenerator: MockDialogueGenerator = MockDialogueGenerator()
    ) {
        self.content = content
        self.repository = repository
        self.mockGenerator = mockGenerator
        director = StoryDirector(chapters: content.chapters)
        retriever = LoreRetriever(entries: content.lore)
        appleModelUnavailableMessage = FoundationModelDialogueGenerator.availability.unavailableMessage
        self.backend = backend ?? .saved
        if self.backend == .local { refreshLocalModel() }
    }

    // MARK: - ローカルLLMの準備

    /// ダウンロード済みならメモリに読み込む。未ダウンロードなら何もしない（容量が大きいので勝手に落とさない）
    func refreshLocalModel() {
        guard localModelState != .ready, localModelTask == nil else { return }
        localModelTask = Task {
            defer { localModelTask = nil }
            if await localGenerator.isDownloaded() {
                await loadLocalModel()
            } else {
                localModelState = .notDownloaded
            }
        }
    }

    /// ユーザーの操作でダウンロード（と読み込み）を始める
    func downloadLocalModel() {
        guard localModelTask == nil else { return }
        localModelTask = Task {
            defer { localModelTask = nil }
            await loadLocalModel()
        }
    }

    private func loadLocalModel() async {
        localModelState = .loading
        do {
            try await localGenerator.preload()
            localModelState = .ready
        } catch {
            localModelState = .failed(error.localizedDescription)
        }
    }

    /// 選んでいるエンジンで今すぐ遊べるか
    var isBackendReady: Bool {
        switch backend {
        case .local: localModelState == .ready
        case .apple: appleModelUnavailableMessage == nil
        case .mock: true
        }
    }

    // MARK: - 表示用

    var hasContinuableSave: Bool {
        guard let save = repository.loadAutoSave() else { return false }
        return !save.isFinished
    }

    var currentLine: DialogueLine? {
        script[safe: cursor] ?? streamingLine
    }

    /// 立ち絵の表情。表示中の行までで最後のヒロインのセリフに合わせる
    var currentEmotion: Emotion {
        if cursor >= script.count, let streamingLine { return streamingLine.emotion }
        return script.prefix(cursor + 1).last { $0.speaker == heroine?.name }?.emotion ?? .normal
    }

    var currentAffection: Int {
        progress.affection
    }

    var showsChoices: Bool {
        !isGenerating && !isTransitioning && !choices.isEmpty && cursor >= script.count - 1
    }

    /// クリックで先に進める状態か（▼インジケータの表示用）
    var canAdvance: Bool {
        !isTransitioning && !showsChoices && cursor < script.count
    }

    var backlog: [DialogueLog] {
        slot.map(repository.allLogs) ?? []
    }

    // MARK: - タイトル

    /// 「はじめから」→ ヒロイン選択画面へ
    func showHeroineSelect() {
        screen = .heroineSelect
    }

    /// 選んだヒロインのルートで新しく始める
    func newGame(heroineID: String) {
        guard content.heroine(id: heroineID) != nil else { return }
        let slot = repository.newGame(heroineID: heroineID)
        self.slot = slot
        progress = slot.progress
        screen = .playing
        startScene()
    }

    func continueGame() {
        guard let save = repository.loadAutoSave(), !save.isFinished else { return }
        slot = save
        progress = save.progress
        screen = .playing
        startScene()
    }

    func returnToTitle() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        isTransitioning = false
        script = []
        choices = []
        screen = .title
    }

    // MARK: - 進行

    func advance() {
        guard screen == .playing, !isTransitioning else { return }

        if cursor < script.count - 1 {
            cursor += 1
            return
        }
        if isGenerating {
            // 用意済みの行を読み終えたら、生成中の行を追いかけて表示する
            cursor = script.count
            return
        }
        if choices.isEmpty, cursor >= script.count - 1 {
            Task { await endScene() }
        }
    }

    func choose(_ option: ChoiceOption) {
        guard let slot, let heroine, let directive, showsChoices else { return }

        let delta = affectionEngine.delta(for: option, heroine: heroine)
        progress.affection = affectionEngine.apply(delta, to: progress.affection)
        progress.turnInScene += 1
        lastAffectionDelta = delta
        choices = []

        script.append(DialogueLine(speaker: GameConstants.playerName, text: option.text))
        cursor = script.count - 1
        repository.appendLog(to: slot, scene: directive, speaker: GameConstants.playerName, text: option.text)
        slot.apply(progress)
        repository.save()

        requestTurn(lastChoice: option.text)
    }

    private func startScene() {
        guard let directive = director.directive(for: progress),
              let heroine = content.heroine(id: progress.heroineID) else {
            finish(with: director.ending(for: progress))
            return
        }
        self.directive = directive
        self.heroine = heroine
        script = [DialogueLine(speaker: nil, text: directive.scene.narration)]
        cursor = 0
        choices = []
        lastAffectionDelta = nil
        generator.prewarm(for: heroine)
        requestTurn(lastChoice: nil)
    }

    private func requestTurn(lastChoice: String?) {
        guard let slot, let heroine, let directive = director.directive(for: progress) else { return }
        self.directive = directive

        let recent = repository.recentLogs(in: slot, heroineID: heroine.id, limit: Self.recentLogLimit)
        let request = TurnRequest(
            heroine: heroine,
            directive: directive,
            affection: currentAffection,
            summaries: repository.summaries(in: slot, heroineID: heroine.id, limit: Self.summaryLimit),
            recentLog: recent,
            lore: retriever.retrieve(
                heroineID: heroine.id,
                sceneTags: directive.scene.tags,
                recentText: recent.map(\.text).joined() + (lastChoice ?? "")
            ),
            lastChoice: lastChoice
        )

        isGenerating = true
        streamingLine = nil
        notice = nil
        let stream = generator.streamTurn(request)

        generationTask = Task {
            do {
                for try await draft in stream {
                    if draft.isFinal {
                        finishTurn(draft)
                    } else {
                        streamingLine = draft.lines.first
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                notice = Self.describe(error)
                finishTurn(fallbackTurn(for: heroine))
            }
        }
    }

    private func finishTurn(_ draft: TurnDraft) {
        guard let slot, let heroine, let directive else { return }
        isGenerating = false
        streamingLine = nil

        let lines = draft.lines.isEmpty ? fallbackTurn(for: heroine).lines : draft.lines
        script.append(contentsOf: lines)
        for line in lines {
            repository.appendLog(to: slot, scene: directive, speaker: heroine.name, text: line.text, emotion: line.emotion)
        }
        slot.totalLineCount += lines.count

        if director.isClosingTurn(progress) {
            choices = []
        } else {
            choices = draft.choices.isEmpty ? ChoiceOption.fallback : draft.choices
        }
        repository.save()
    }

    private func endScene() async {
        guard let slot, let heroine, let directive, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        let summary: String
        do {
            summary = try await generator.summarize(SummaryRequest(
                heroine: heroine,
                directive: directive,
                log: repository.sceneLogs(in: slot, sceneID: directive.scene.id)
            ))
        } catch {
            summary = "\(directive.scene.location)で\(heroine.name)と過ごした。"
        }
        guard screen == .playing else { return }
        repository.addSummary(to: slot, scene: directive, text: summary)

        switch director.nextStep(after: progress) {
        case .scene(let next):
            progress = next
            slot.apply(next)
            repository.save()
            startScene()
        case .ending(let ending):
            finish(with: ending)
        }
    }

    private func finish(with ending: Ending) {
        slot?.isFinished = true
        repository.save()
        screen = .ending(ending)
    }

    // MARK: - フォールバック

    private func fallbackTurn(for heroine: Heroine) -> TurnDraft {
        TurnDraft(
            lines: [DialogueLine(speaker: heroine.name, text: heroine.fallbackLines.randomElement() ?? "……")],
            choices: ChoiceOption.fallback,
            isFinal: true
        )
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? LanguageModelError else {
            return "セリフの生成に失敗したため、定型セリフに差し替えました。"
        }
        return switch error {
        case .guardrailViolation, .refusal:
            "安全フィルタが反応したため、定型セリフに差し替えました。"
        case .contextSizeExceeded:
            "プロンプトが長すぎたため、定型セリフに差し替えました。"
        default:
            "セリフの生成に失敗したため、定型セリフに差し替えました。"
        }
    }
}

extension ChoiceOption {
    static var fallback: [ChoiceOption] {
        [
            ChoiceOption(text: "うん、そうだね", tone: .kind, suggestedDelta: 1),
            ChoiceOption(text: "もう少し聞かせてよ", tone: .honest, suggestedDelta: 1),
            ChoiceOption(text: "ふーん", tone: .cool, suggestedDelta: 0),
        ]
    }
}
