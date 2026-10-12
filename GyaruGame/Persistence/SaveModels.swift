import Foundation
import SwiftData

/// オートセーブ。進行はシーンの区切りでだけ書き込み、つづきからはシーンの頭から始める
@Model
final class SaveSlot {
    @Attribute(.unique) var slotID: Int
    var sceneQueue: [String] = []
    var sceneIndex: Int = 0
    var routeRaw: String?
    var tokimeki: Int = 0
    var trust: Int = 0
    var nori: Int = 0
    var isFinished: Bool = false
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \DialogueLog.slot)
    var logs: [DialogueLog] = []

    init(slotID: Int) {
        self.slotID = slotID
    }

    var progress: GameProgress {
        GameProgress(
            sceneQueue: sceneQueue,
            sceneIndex: sceneIndex,
            route: routeRaw.flatMap(Axis.init(rawValue:)),
            feelings: Feelings(tokimeki: tokimeki, trust: trust, nori: nori)
        )
    }

    func apply(_ progress: GameProgress) {
        sceneQueue = progress.sceneQueue
        sceneIndex = progress.sceneIndex
        routeRaw = progress.route?.rawValue
        tokimeki = progress.feelings.tokimeki
        trust = progress.feelings.trust
        nori = progress.feelings.nori
        updatedAt = .now
    }
}

/// バックログ表示用の会話ログ
@Model
final class DialogueLog {
    var order: Int
    var sceneID: String
    var speaker: String
    var text: String
    var emotionRaw: String
    var slot: SaveSlot?

    init(order: Int, sceneID: String, speaker: String, text: String, emotion: Emotion) {
        self.order = order
        self.sceneID = sceneID
        self.speaker = speaker
        self.text = text
        emotionRaw = emotion.rawValue
    }
}
