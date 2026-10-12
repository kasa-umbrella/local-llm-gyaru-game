import Foundation
import SwiftData

/// セーブデータへのアクセスをまとめる。今はオートセーブ用の1スロットのみ
final class SaveRepository {
    static let autoSaveSlotID = 0
    /// ヒロイン3人・好感度1本だった頃のセーブとは互換性がないので、別のストアに保存する
    private static let storeName = "SaveV2"

    /// ModelContext はコンテナが解放されると使えなくなるので、コンテナごと保持する
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([SaveSlot.self, DialogueLog.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory))
    }

    func loadAutoSave() -> SaveSlot? {
        let id = Self.autoSaveSlotID
        let descriptor = FetchDescriptor<SaveSlot>(predicate: #Predicate { $0.slotID == id })
        return try? context.fetch(descriptor).first
    }

    func newGame() -> SaveSlot {
        if let existing = loadAutoSave() {
            context.delete(existing)
            try? context.save()
        }
        let slot = SaveSlot(slotID: Self.autoSaveSlotID)
        context.insert(slot)
        save()
        return slot
    }

    func appendLog(to slot: SaveSlot, sceneID: String, speaker: String, text: String, emotion: Emotion = .normal) {
        slot.logs.append(DialogueLog(order: slot.logs.count, sceneID: sceneID, speaker: speaker, text: text, emotion: emotion))
    }

    /// つづきからシーンをやり直すときに、途中まで読んだ分のログを消す
    func removeLogs(in slot: SaveSlot, sceneID: String) {
        for log in slot.logs where log.sceneID == sceneID {
            context.delete(log)
        }
        slot.logs.removeAll { $0.sceneID == sceneID }
    }

    func allLogs(in slot: SaveSlot) -> [DialogueLog] {
        slot.logs.sorted { $0.order < $1.order }
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("[SaveRepository] save failed: \(error)")
        }
    }
}
