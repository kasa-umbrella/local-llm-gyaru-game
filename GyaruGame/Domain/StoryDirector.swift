import Foundation

/// セーブデータから切り離した進行状態。StoryDirector はこれだけを見て判断する
nonisolated struct GameProgress: Equatable, Sendable {
    /// この周回で流すシーンの順番（共通の導入＋引いたイベント。分岐後はルートのシーンが足される）
    var sceneQueue: [String] = []
    var sceneIndex = 0
    /// 分岐のくじで決まったルート（分岐前は nil）
    var route: Axis?
    var feelings = Feelings()
    /// ルートのシーンを流し終えた時点で決まった結末（それまでは nil）
    var endingKind: Ending.Kind?
}

nonisolated struct Ending: Equatable, Sendable {
    enum Kind: String, Sendable {
        case good, normal
    }

    let kind: Kind
    let route: Axis
}

nonisolated enum NextStep: Equatable, Sendable {
    case scene(GameProgress)
    case ending(Ending)
}

/// 周回ごとの山札、シーンの順番、分岐のくじを決める「監督」。
/// どの選択肢を選べばどのルートに行く、という対応は持たない。気持ちの3軸で重みを付けたくじで決める
nonisolated struct StoryDirector: Sendable {
    /// ルートの軸がこの値以上なら Good エンディング
    static let goodEndingThreshold = 15
    /// くじの重みの底上げ。大きいほど、いちばん高い軸以外のルートにも転びやすい
    static let lotteryBase = 5

    let story: Story

    func scene(for progress: GameProgress) -> SceneDefinition? {
        progress.sceneQueue[safe: progress.sceneIndex].flatMap(story.scene(id:))
    }

    /// 新しい周回。山札からイベントを引き、原作の記事の月の順に並べる
    func newGame(using random: inout some RandomNumberGenerator) -> GameProgress {
        let drawn = story.deck.shuffled(using: &random).prefix(story.deckDrawCount)
        let ordered = drawn
            .compactMap(story.scene(id:))
            .enumerated()
            .sorted { ($0.element.month, $0.offset) < ($1.element.month, $1.offset) }
            .map(\.element.id)
        return GameProgress(sceneQueue: story.prologue + ordered)
    }

    /// シーン終了後の遷移先を決める。中盤のイベントを流し終えたら、くじでルートを決める。
    /// ルートのシーンを流し終えたら結末（GOOD / NORMAL）を決め、その結末のシーンがあれば流してからエンディングにする
    func nextStep(after progress: GameProgress, using random: inout some RandomNumberGenerator) -> NextStep {
        var next = progress
        next.sceneIndex += 1
        if next.sceneIndex < next.sceneQueue.count {
            return .scene(next)
        }
        if next.route == nil {
            let axis = drawRoute(for: next.feelings, using: &random)
            next.route = axis
            let scenes = story.route(for: axis)?.scenes ?? []
            if !scenes.isEmpty {
                next.sceneQueue += scenes
                return .scene(next)
            }
        }
        if next.endingKind == nil {
            let ending = ending(for: next)
            next.endingKind = ending.kind
            if let sceneID = story.route(for: ending.route)?.endingScenes?[ending.kind.rawValue] {
                next.sceneQueue.append(sceneID)
                return .scene(next)
            }
        }
        return .ending(ending(for: next))
    }

    /// くじの重み。いちばん低い軸を基準に、差分＋底上げの分だけ当たりやすくする
    func routeWeights(for feelings: Feelings) -> [Axis: Int] {
        let lowest = Axis.allCases.map { feelings[$0] }.min() ?? 0
        return Dictionary(uniqueKeysWithValues: Axis.allCases.map { ($0, feelings[$0] - lowest + Self.lotteryBase) })
    }

    func drawRoute(for feelings: Feelings, using random: inout some RandomNumberGenerator) -> Axis {
        let weights = routeWeights(for: feelings)
        var ticket = Int.random(in: 0..<weights.values.reduce(0, +), using: &random)
        for axis in Axis.allCases {
            let weight = weights[axis] ?? 0
            if ticket < weight { return axis }
            ticket -= weight
        }
        return feelings.strongest
    }

    /// 結末がもう決まっていればそれを使う（結末のシーンとエンディング画面を食い違わせない）
    func ending(for progress: GameProgress) -> Ending {
        let route = progress.route ?? progress.feelings.strongest
        let kind = progress.endingKind ?? (progress.feelings[route] >= Self.goodEndingThreshold ? .good : .normal)
        return Ending(kind: kind, route: route)
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
