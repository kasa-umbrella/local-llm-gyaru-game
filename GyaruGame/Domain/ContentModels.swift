import Foundation

/// 主人公の名前（将来的には設定画面で変更できるようにする）
nonisolated enum GameConstants {
    static let playerName = "ユウキ"
    static let playerProfile = "26歳のWebエンジニア"
}

/// 表情。立ち絵の差分切り替えに使う（アセット名: `<heroineID>_<emotion>`）
nonisolated enum Emotion: String, Codable, CaseIterable, Sendable {
    case normal, smile, shy, angry, sad, surprised
}

nonisolated struct Heroine: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let firstPerson: String
    let callsPlayer: String
    /// 判定役の LLM に渡す人物像
    let profile: String
    let themeColor: String
}

/// 1つのシーン。中身（セリフと選択肢）は `script_<id>.json` に人が書く
nonisolated struct SceneDefinition: Codable, Identifiable, Sendable {
    let id: String
    let location: String
    let background: String
    /// 原作の記事が書かれた月。山札から引いたイベントはこの順に並べる
    let month: Int
}

/// 最終盤のルート。分岐のくじで1つに決まる
nonisolated struct Route: Codable, Sendable {
    let axis: Axis
    let title: String
    /// ルートに入ってから順に流すシーン
    let scenes: [String]
    /// "good" / "normal" のエンディングの文
    let endings: [String: String]
}

/// 物語の骨組み。共通の導入 → 山札から引いたイベント → 分岐したルート の順に進む
nonisolated struct Story: Codable, Sendable {
    let prologue: [String]
    /// 中盤のイベントの山札（1周で deckDrawCount 枚だけ引く）
    let deck: [String]
    let deckDrawCount: Int
    let routes: [Route]
    let scenes: [SceneDefinition]

    func scene(id: String) -> SceneDefinition? {
        scenes.first { $0.id == id }
    }

    func route(for axis: Axis) -> Route? {
        routes.first { $0.axis == axis }
    }
}

/// バンドル内JSONから読み込むマスターデータ一式
nonisolated struct GameContent: Sendable {
    let heroine: Heroine
    let story: Story
    /// シーンID → 人が書いたシナリオ
    let scripts: [String: SceneScript]

    func script(for sceneID: String) -> SceneScript? {
        scripts[sceneID]
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> GameContent {
        GameContent(
            heroine: try decode("heroine", from: bundle),
            story: try decode("story", from: bundle),
            scripts: try loadScripts(from: bundle)
        )
    }

    /// `script_<シーンID>.json` をすべて読み込む
    private static func loadScripts(from bundle: Bundle) throws -> [String: SceneScript] {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("script_") }
        let scripts = try urls.map { try JSONDecoder().decode(SceneScript.self, from: Data(contentsOf: $0)) }
        return Dictionary(uniqueKeysWithValues: scripts.map { ($0.sceneID, $0) })
    }

    private static func decode<T: Decodable>(_ name: String, from bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
