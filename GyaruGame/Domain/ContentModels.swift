import Foundation
import FoundationModels

/// 主人公の名前（将来的には設定画面で変更できるようにする）
nonisolated enum GameConstants {
    static let playerName = "ユウキ"
    static let playerProfile = "30歳の会社員"
    static let affectionRange = 0...100
}

/// 表情。立ち絵の差分切り替えに使う（アセット名: `<heroineID>_<emotion>`）
@Generable
nonisolated enum Emotion: String, Codable, CaseIterable, Sendable {
    case normal, smile, shy, angry, sad, surprised
}

/// 選択肢の「方向性」。ヒロインごとの相性表で好感度を補正する
@Generable
nonisolated enum ChoiceTone: String, Codable, CaseIterable, Sendable {
    case kind, teasing, honest, cool, romantic, rude
}

nonisolated struct Heroine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// 主人公との関係（選択画面に表示）
    let role: String
    /// 選択画面のひとこと紹介
    let tagline: String
    let firstPerson: String
    let callsPlayer: String
    let profile: String
    let speechRules: [String]
    let sampleLines: [String]
    /// ChoiceTone.rawValue -> 補正値
    let tonePreferences: [String: Int]
    /// 生成失敗時に使う定型セリフ
    let fallbackLines: [String]
    let themeColor: String

    func preference(for tone: ChoiceTone) -> Int {
        tonePreferences[tone.rawValue] ?? 0
    }
}

nonisolated struct Chapter: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let scenes: [SceneDefinition]
}

nonisolated struct SceneDefinition: Codable, Identifiable, Sendable {
    /// 選んだヒロインが誰であっても使う共通シーンの特殊キャスト
    static let selectedHeroineCast = "@heroine"

    let id: String
    let cast: String
    let location: String
    let background: String
    let narration: String
    let tags: [String]
    let goal: String
    /// 選択肢を出すターン数。この数だけ選んだら締めのターンに入る
    let turns: Int
}

nonisolated struct LoreEntry: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let heroineID: String
    let tags: [String]
    let keywords: [String]
    let text: String
}

/// バンドル内JSONから読み込むマスターデータ一式
nonisolated struct GameContent: Sendable {
    let heroines: [Heroine]
    let chapters: [Chapter]
    let lore: [LoreEntry]

    func heroine(id: String) -> Heroine? {
        heroines.first { $0.id == id }
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> GameContent {
        GameContent(
            heroines: try decode("heroines", from: bundle),
            chapters: try decode("chapters", from: bundle),
            lore: try decode("lore", from: bundle)
        )
    }

    private static func decode<T: Decodable>(_ name: String, from bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
