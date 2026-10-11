import Foundation
import SwiftData

@Model
final class SaveSlot {
    @Attribute(.unique) var slotID: Int
    /// タイトル後に選んだヒロイン
    var heroineID: String = ""
    var affection: Int = 0
    var chapterIndex: Int
    var sceneIndex: Int
    var turnInScene: Int
    /// これまでに表示したヒロインのセリフ数
    var totalLineCount: Int
    var isFinished: Bool
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \DialogueLog.slot)
    var logs: [DialogueLog] = []

    @Relationship(deleteRule: .cascade, inverse: \MemorySummary.slot)
    var summaries: [MemorySummary] = []

    init(slotID: Int, heroineID: String) {
        self.slotID = slotID
        self.heroineID = heroineID
        chapterIndex = 0
        sceneIndex = 0
        turnInScene = 0
        totalLineCount = 0
        isFinished = false
        updatedAt = .now
    }

    var progress: GameProgress {
        GameProgress(
            heroineID: heroineID,
            chapterIndex: chapterIndex,
            sceneIndex: sceneIndex,
            turnInScene: turnInScene,
            affection: affection
        )
    }

    func apply(_ progress: GameProgress) {
        heroineID = progress.heroineID
        chapterIndex = progress.chapterIndex
        sceneIndex = progress.sceneIndex
        turnInScene = progress.turnInScene
        affection = progress.affection
        updatedAt = .now
    }
}

/// バックログ表示と、直近の文脈として LLM に渡すための会話ログ
@Model
final class DialogueLog {
    var order: Int
    var chapterIndex: Int
    var sceneID: String
    var heroineID: String
    var speaker: String
    var text: String
    var emotionRaw: String
    var slot: SaveSlot?

    init(order: Int, chapterIndex: Int, sceneID: String, heroineID: String, speaker: String, text: String, emotion: Emotion) {
        self.order = order
        self.chapterIndex = chapterIndex
        self.sceneID = sceneID
        self.heroineID = heroineID
        self.speaker = speaker
        self.text = text
        emotionRaw = emotion.rawValue
    }
}

/// シーンごとの要約。長期記憶として次のシーン以降のプロンプトに入れる
@Model
final class MemorySummary {
    var order: Int
    var heroineID: String
    var chapterIndex: Int
    var sceneID: String
    var text: String
    var slot: SaveSlot?

    init(order: Int, heroineID: String, chapterIndex: Int, sceneID: String, text: String) {
        self.order = order
        self.heroineID = heroineID
        self.chapterIndex = chapterIndex
        self.sceneID = sceneID
        self.text = text
    }
}
