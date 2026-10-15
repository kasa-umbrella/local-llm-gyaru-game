import Foundation
import Observation

/// ゲーム全体の状態遷移。
/// StoryDirector（監督）が決めた順に人が書いたシナリオを流し、選んだ選択肢（や入力した一言）の結果だけを FeelingJudging（判定役）に判定させる
@Observable
final class GameViewModel {
    enum Screen: Equatable {
        case title
        case playing
        case ending(Ending)
    }

    /// 判定役に渡す、選択肢が出るまでの流れの行数
    private static let judgeContextLimit = 8

    let content: GameContent
    private let director: StoryDirector
    private let repository: SaveRepository
    private let localJudge: LocalLLMJudge
    /// 判定役。本番は localJudge、テストではスタブ
    private let judge: FeelingJudging
    /// 山札・選択肢の候補・気分・分岐のくじに使う乱数
    private var random: SeededGenerator

    private(set) var localModelState: LocalModelState = .notDownloaded
    private var localModelTask: Task<Void, Never>?

    private(set) var screen: Screen = .title
    private(set) var progress = GameProgress()
    private(set) var scene: SceneDefinition?
    /// 表示中の背景（アセット名の `bg_` のあと）。シーンの頭は scene.background で、途中で切り替わる
    private(set) var background = ""
    /// このシーンのひよりの気分（判定にだけ効かせる）
    private(set) var mood: Mood = .calm

    /// このシーンで表示した行（地の文・ヒロイン・主人公）
    private(set) var script: [DialogueLine] = []
    /// 表示中の行
    private(set) var cursor = 0
    /// シナリオの登場・退場を最後まで処理した時点で、ヒロインが画面に出ているか
    private var heroineOnStage = false
    private(set) var choices: [ChoiceOption] = []
    /// 表示中の選択肢に、自由入力の欄も付けるか
    private var choiceAllowsFreeInput = false
    /// 自由入力への反応を、判定役が選ぶのを待っている間。この間は先へ進めない
    private(set) var isAwaitingReaction = false
    /// シーンの終わりに、判定が出そろうのを待っている間
    private(set) var isTransitioning = false
    /// 直前の選択肢の判定（開発用の表示に使う）
    private(set) var lastJudgment: Feelings?
    /// 直前の判定で動いた軸（立ち絵の上に出す）。判定が出るたびに作り直すので、同じ結果が続いても毎回表示される
    private(set) var feelingFeedback: FeelingFeedback?

    private var slot: SaveSlot?
    private var sceneScript: SceneScript?
    private var beatIndex = 0
    /// 表示中の選択肢と同じ順に並べた、人が書いた候補
    private var shownCandidates: [ScriptChoice] = []
    /// このシーンで選んだ選択肢の判定。モデルを取り合わないよう、前の判定が終わってから次を始める
    private var judgeTasks: [Task<Void, Never>] = []
    /// 自由入力でもう出した反応のセリフ。同じセリフが続かないようにする
    private var usedFreeReplies: Set<String> = []

    /// judge を渡さなければローカルLLM（Qwen3.5）で判定する。渡したとき（テスト）はモデルを読み込まない
    init(content: GameContent, repository: SaveRepository, judge: FeelingJudging? = nil, seed: UInt64? = nil) {
        self.content = content
        self.repository = repository
        let localJudge = LocalLLMJudge()
        self.localJudge = localJudge
        self.judge = judge ?? localJudge
        random = seed.map(SeededGenerator.init(seed:)) ?? SeededGenerator()
        director = StoryDirector(story: content.story)
        if judge == nil {
            refreshLocalModel()
        } else {
            localModelState = .ready
        }
    }

    // MARK: - ローカルLLMの準備

    /// ダウンロード済みならメモリに読み込む。未ダウンロードなら何もしない（容量が大きいので勝手に落とさない）
    func refreshLocalModel() {
        guard localModelState != .ready, localModelTask == nil else { return }
        localModelTask = Task {
            defer { localModelTask = nil }
            if await localJudge.isDownloaded() {
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
            try await localJudge.preload()
            localModelState = .ready
        } catch {
            localModelState = .failed(error.localizedDescription)
        }
    }

    /// モデルの準備ができていて、今すぐ遊べるか
    var isModelReady: Bool {
        localModelState == .ready
    }

    // MARK: - 表示用

    var heroine: Heroine {
        content.heroine
    }

    var hasContinuableSave: Bool {
        guard let save = repository.loadAutoSave() else { return false }
        return !save.isFinished
    }

    var currentLine: DialogueLine? {
        script[safe: cursor]
    }

    /// 立ち絵の表情。表示中の行までで最後のヒロインのセリフに合わせる
    var currentEmotion: Emotion {
        script.prefix(cursor + 1).last { $0.speaker == heroine.name }?.emotion ?? .normal
    }

    /// 立ち絵を出すか。最後の行を表示中は、そのあとに処理した登場・退場（選択肢の直前など）も反映する
    var isHeroineOnStage: Bool {
        guard cursor < script.count - 1 else { return heroineOnStage }
        return script[cursor].showsHeroine
    }

    var showsChoices: Bool {
        !isTransitioning && !choices.isEmpty && cursor >= script.count - 1
    }

    /// 選択肢のほかに、自分の言葉で伝える入力欄を出せるか
    var allowsFreeInput: Bool {
        showsChoices && choiceAllowsFreeInput
    }

    /// クリックで先に進める状態か（▼インジケータの表示用）
    var canAdvance: Bool {
        !isTransitioning && !isAwaitingReaction && !showsChoices && cursor < script.count
    }

    var backlog: [DialogueLog] {
        slot.map(repository.allLogs) ?? []
    }

    // MARK: - タイトル

    func newGame() {
        let slot = repository.newGame()
        self.slot = slot
        progress = director.newGame(using: &random)
        slot.apply(progress)
        repository.save()
        usedFreeReplies = []
        screen = .playing
        startScene()
    }

    func continueGame() {
        guard let save = repository.loadAutoSave(), !save.isFinished else { return }
        slot = save
        progress = save.progress
        usedFreeReplies = []
        screen = .playing
        startScene()
    }

    func returnToTitle() {
        cancelJudgments()
        sceneScript = nil
        isTransitioning = false
        script = []
        choices = []
        choiceAllowsFreeInput = false
        screen = .title
    }

    // MARK: - 進行

    func advance() {
        guard screen == .playing, !isTransitioning, !isAwaitingReaction else { return }
        if cursor < script.count - 1 {
            cursor += 1
        } else if choices.isEmpty {
            playNextBeat()
        }
    }

    func choose(_ option: ChoiceOption) {
        guard showsChoices,
              let index = choices.firstIndex(where: { $0.id == option.id }),
              let picked = shownCandidates[safe: index],
              let scene else { return }

        // 判定には、選ぶ前までの流れを渡す
        let request = JudgeRequest(
            heroine: heroine,
            scene: scene,
            mood: mood,
            feelings: progress.feelings,
            recentLines: Array(script.suffix(Self.judgeContextLimit)),
            playerLine: option.text,
            reaction: picked.reaction.text
        )
        choices = []
        shownCandidates = []
        choiceAllowsFreeInput = false
        appendLine(DialogueLine(speaker: GameConstants.playerName, text: option.text), showNow: true)
        // 主人公のセリフを読んでから反応へ進めるよう、反応はカーソルを動かさずに積む
        appendLine(DialogueLine(speaker: heroine.name, text: picked.reaction.text, emotion: picked.reaction.emotion), showNow: false)
        requestJudgment(request)
    }

    /// プレイヤーが入力した一言を言う。ひよりの反応は、判定役が人の書いた反応の中から選ぶ（選ぶまで先へ進めない）
    func submitFreeInput(_ text: String) {
        guard allowsFreeInput, let line = FreeInput.sanitized(text), let scene else { return }

        let request = JudgeRequest(
            heroine: heroine,
            scene: scene,
            mood: mood,
            feelings: progress.feelings,
            recentLines: Array(script.suffix(Self.judgeContextLimit)),
            playerLine: line,
            reaction: nil
        )
        choices = []
        shownCandidates = []
        choiceAllowsFreeInput = false
        appendLine(DialogueLine(speaker: GameConstants.playerName, text: line), showNow: true)
        isAwaitingReaction = true
        chainJudgment { [self] in
            let judgment = await judge.judgedFreeInput(request)
            guard !Task.isCancelled else { return }
            let reply = content.freeReplies.pick(for: judgment.kind, avoiding: usedFreeReplies, using: &random)
            usedFreeReplies.insert(reply.text)
            // 入力した一言を読んでから反応へ進めるよう、反応はカーソルを動かさずに積む
            appendLine(DialogueLine(speaker: heroine.name, text: reply.text, emotion: reply.emotion), showNow: false)
            isAwaitingReaction = false
            apply(judgment.delta)
        }
    }

    /// 判定は裏で行い、出たらすぐ気持ちに足す。画面の進行は待たせない
    private func requestJudgment(_ request: JudgeRequest) {
        chainJudgment { [self] in
            let delta = await judge.judgedDelta(request)
            guard !Task.isCancelled else { return }
            apply(delta)
        }
    }

    /// 判定を、前の判定が終わってから始める（モデルを取り合わないため）
    private func chainJudgment(_ work: @escaping @MainActor () async -> Void) {
        let previous = judgeTasks.last
        judgeTasks.append(Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        })
    }

    private func apply(_ delta: Feelings) {
        progress.feelings = progress.feelings.adding(delta)
        lastJudgment = delta
        feelingFeedback = FeelingFeedback(delta: delta)
    }

    private func cancelJudgments() {
        judgeTasks.forEach { $0.cancel() }
        judgeTasks = []
        isAwaitingReaction = false
    }

    private func startScene() {
        guard let slot, let scene = director.scene(for: progress), let sceneScript = content.script(for: scene.id) else {
            finish(with: director.ending(for: progress))
            return
        }
        cancelJudgments()
        // つづきからの場合、途中まで読んでいた分のログは捨ててシーンの頭からやり直す
        repository.removeLogs(in: slot, sceneID: scene.id)
        self.scene = scene
        self.sceneScript = sceneScript
        background = scene.background
        mood = Mood.allCases.randomElement(using: &random) ?? .calm
        beatIndex = 0
        script = []
        cursor = 0
        heroineOnStage = false
        choices = []
        shownCandidates = []
        choiceAllowsFreeInput = false
        lastJudgment = nil
        judge.prewarm()
        playNextBeat()
    }

    /// 次のビートを出す。最後まで出したらシーンを終える
    private func playNextBeat() {
        guard let sceneScript else { return }
        guard beatIndex < sceneScript.beats.count else {
            Task { await endScene() }
            return
        }
        let beat = sceneScript.beats[beatIndex]
        beatIndex += 1

        switch beat {
        case .narration(let text):
            appendLine(DialogueLine(speaker: nil, text: text), showNow: true)
        case .line(let line):
            appendLine(DialogueLine(speaker: heroine.name, text: line.text, emotion: line.emotion), showNow: true)
        case .speech(let speech):
            appendLine(DialogueLine(speaker: speech.displayName, text: speech.text), showNow: true)
        case .choice(let candidates, let allowsFreeInput):
            // 候補が多ければ毎回ちがう組み合わせを、並びも混ぜて出す
            shownCandidates = Array(candidates.shuffled(using: &random).prefix(ScriptChoice.shownCount))
            choices = shownCandidates.map { ChoiceOption(text: $0.text) }
            choiceAllowsFreeInput = allowsFreeInput
        case .enter:
            heroineOnStage = true
            playNextBeat()
        case .exit:
            heroineOnStage = false
            playNextBeat()
        case .background(let name):
            background = name
            playNextBeat()
        }
    }

    private func endScene() async {
        guard let slot, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        // ルートのくじと保存の前に、このシーンの判定が出そろうのを待つ
        for task in judgeTasks {
            await task.value
        }
        judgeTasks = []
        guard screen == .playing else { return }

        switch director.nextStep(after: progress, using: &random) {
        case .scene(let next):
            progress = next
            slot.apply(next)
            repository.save()
            startScene()
        case .ending(let ending):
            progress.route = ending.route
            slot.apply(progress)
            finish(with: ending)
        }
    }

    private func finish(with ending: Ending) {
        slot?.isFinished = true
        repository.save()
        screen = .ending(ending)
    }

    private func appendLine(_ line: DialogueLine, showNow: Bool) {
        var line = line
        line.showsHeroine = heroineOnStage
        script.append(line)
        if showNow { cursor = script.count - 1 }
        guard let slot, let scene, let speaker = line.speaker else { return }
        repository.appendLog(to: slot, sceneID: scene.id, speaker: speaker, text: line.text, emotion: line.emotion)
    }
}

/// 選択肢の判定で動いた軸。どれも動かなかったときは作らない
nonisolated struct FeelingFeedback: Equatable, Sendable {
    struct Change: Equatable, Sendable {
        let axis: Axis
        let delta: Int
    }

    let id = UUID()
    let changes: [Change]

    init?(delta: Feelings) {
        changes = Axis.allCases.compactMap { delta[$0] == 0 ? nil : Change(axis: $0, delta: delta[$0]) }
        if changes.isEmpty { return nil }
    }
}
