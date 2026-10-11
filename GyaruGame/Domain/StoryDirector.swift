import Foundation

/// セーブデータから切り離した進行状態。StoryDirector はこれだけを見て判断する
nonisolated struct GameProgress: Equatable, Sendable {
    /// タイトル後に選んだヒロイン
    var heroineID: String
    var chapterIndex = 0
    /// 選んだヒロインのシーンだけを数えたインデックス
    var sceneIndex = 0
    var turnInScene = 0
    var affection = 0
}

nonisolated enum ScenePhase: String, Sendable {
    case intro, development, closing

    var instruction: String {
        switch self {
        case .intro: "シーンの導入。ヒロインから主人公に話しかけて場面を始める"
        case .development: "会話を発展させ、シーンの目標に向かって少しずつ距離を縮める"
        case .closing: "シーンの締め。主人公の返答に反応し、会話を自然に終わらせる"
        }
    }
}

/// LLM に渡す「演出指示」
nonisolated struct SceneDirective: Sendable {
    let chapterNumber: Int
    let chapterTitle: String
    let scene: SceneDefinition
    let heroineID: String
    let phase: ScenePhase
    let turnsLeft: Int
}

nonisolated struct Ending: Equatable, Sendable {
    enum Kind: Sendable {
        case good, normal, bad
    }

    let kind: Kind
    let heroineID: String
}

nonisolated enum NextStep: Equatable, Sendable {
    case scene(GameProgress)
    case ending(Ending)
}

/// 選んだヒロインのルートについて、章・シーン・ターンの進行を決定的に管理する「監督」
nonisolated struct StoryDirector: Sendable {
    static let goodEndingThreshold = 55
    static let normalEndingThreshold = 30

    let chapters: [Chapter]

    func chapter(for progress: GameProgress) -> Chapter? {
        chapters[safe: progress.chapterIndex]
    }

    /// 章の中から、選んだヒロインが登場するシーンだけを取り出す
    func scenes(in chapter: Chapter, for heroineID: String) -> [SceneDefinition] {
        chapter.scenes.filter { $0.cast == heroineID || $0.cast == SceneDefinition.selectedHeroineCast }
    }

    func scene(for progress: GameProgress) -> SceneDefinition? {
        guard let chapter = chapter(for: progress) else { return nil }
        return scenes(in: chapter, for: progress.heroineID)[safe: progress.sceneIndex]
    }

    func phase(for progress: GameProgress, in scene: SceneDefinition) -> ScenePhase {
        if progress.turnInScene >= scene.turns { return .closing }
        return progress.turnInScene == 0 ? .intro : .development
    }

    /// 締めのターン（選択肢を出さずにシーンを終える）かどうか
    func isClosingTurn(_ progress: GameProgress) -> Bool {
        guard let scene = scene(for: progress) else { return true }
        return progress.turnInScene >= scene.turns
    }

    func directive(for progress: GameProgress) -> SceneDirective? {
        guard let chapter = chapter(for: progress), let scene = scene(for: progress) else { return nil }
        return SceneDirective(
            chapterNumber: progress.chapterIndex + 1,
            chapterTitle: chapter.title,
            scene: scene,
            heroineID: progress.heroineID,
            phase: phase(for: progress, in: scene),
            turnsLeft: max(scene.turns - progress.turnInScene, 0)
        )
    }

    /// シーン終了後の遷移先を決める。そのヒロインのシーンがない章は飛ばす
    func nextStep(after progress: GameProgress) -> NextStep {
        var next = progress
        next.turnInScene = 0
        next.sceneIndex += 1

        while let chapter = chapter(for: next) {
            if next.sceneIndex < scenes(in: chapter, for: next.heroineID).count {
                return .scene(next)
            }
            next.chapterIndex += 1
            next.sceneIndex = 0
        }
        return .ending(ending(for: progress))
    }

    func ending(for progress: GameProgress) -> Ending {
        let kind: Ending.Kind = switch progress.affection {
        case Self.goodEndingThreshold...: .good
        case Self.normalEndingThreshold...: .normal
        default: .bad
        }
        return Ending(kind: kind, heroineID: progress.heroineID)
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
