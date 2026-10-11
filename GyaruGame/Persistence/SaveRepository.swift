import Foundation
import SwiftData

/// セーブデータへのアクセスをまとめる。今はオートセーブ用の1スロットのみ
final class SaveRepository {
    static let autoSaveSlotID = 0

    /// ModelContext はコンテナが解放されると使えなくなるので、コンテナごと保持する
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([SaveSlot.self, DialogueLog.self, MemorySummary.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    func loadAutoSave() -> SaveSlot? {
        let id = Self.autoSaveSlotID
        let descriptor = FetchDescriptor<SaveSlot>(predicate: #Predicate { $0.slotID == id })
        return try? context.fetch(descriptor).first
    }

    func newGame(heroineID: String) -> SaveSlot {
        if let existing = loadAutoSave() {
            context.delete(existing)
            try? context.save()
        }
        let slot = SaveSlot(slotID: Self.autoSaveSlotID, heroineID: heroineID)
        context.insert(slot)
        save()
        return slot
    }

    func appendLog(to slot: SaveSlot, scene: SceneDirective, speaker: String, text: String, emotion: Emotion = .normal) {
        let log = DialogueLog(
            order: slot.logs.count,
            chapterIndex: scene.chapterNumber - 1,
            sceneID: scene.scene.id,
            heroineID: scene.heroineID,
            speaker: speaker,
            text: text,
            emotion: emotion
        )
        slot.logs.append(log)
    }

    func recentLogs(in slot: SaveSlot, heroineID: String, limit: Int) -> [LogEntry] {
        slot.logs
            .filter { $0.heroineID == heroineID }
            .sorted { $0.order < $1.order }
            .suffix(limit)
            .map { LogEntry(speaker: $0.speaker, text: $0.text) }
    }

    func sceneLogs(in slot: SaveSlot, sceneID: String) -> [LogEntry] {
        slot.logs
            .filter { $0.sceneID == sceneID }
            .sorted { $0.order < $1.order }
            .map { LogEntry(speaker: $0.speaker, text: $0.text) }
    }

    func allLogs(in slot: SaveSlot) -> [DialogueLog] {
        slot.logs.sorted { $0.order < $1.order }
    }

    func addSummary(to slot: SaveSlot, scene: SceneDirective, text: String) {
        slot.summaries.append(MemorySummary(
            order: slot.summaries.count,
            heroineID: scene.heroineID,
            chapterIndex: scene.chapterNumber - 1,
            sceneID: scene.scene.id,
            text: text
        ))
    }

    /// 要約は古いものから溜まっていくので、直近の数件だけをプロンプトに入れる
    func summaries(in slot: SaveSlot, heroineID: String, limit: Int) -> [String] {
        slot.summaries
            .filter { $0.heroineID == heroineID }
            .sorted { $0.order < $1.order }
            .suffix(limit)
            .map(\.text)
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("[SaveRepository] save failed: \(error)")
        }
    }
}
