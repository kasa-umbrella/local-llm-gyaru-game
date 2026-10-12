import Foundation
import Testing
@testable import GyaruGame

/// ローカルLLM（Qwen3.5 on MLX）の判定を、実際のシナリオの選択肢で確かめる。
/// 初回はモデルのダウンロードが走るので、環境変数を付けたときだけ実行する:
/// `TEST_RUNNER_RUN_LOCAL_LLM_TESTS=1 xcodebuild test ...`
/// モデルを変えるときは `TEST_RUNNER_LOCAL_LLM_MODEL=mlx-community/Qwen3.5-4B-MLX-4bit` も付ける。
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_LOCAL_LLM_TESTS"] != nil), .serialized)
struct LocalLLMSmokeTests {
    private static let modelID = ProcessInfo.processInfo.environment["LOCAL_LLM_MODEL"] ?? LocalLLMJudge.modelID
    private static let judge = LocalLLMJudge(modelID: modelID)

    @Test(.timeLimit(.minutes(30)))
    func preloadsModel() async throws {
        try await Self.judge.preload()
    }

    /// シーンの全選択肢を、気分を変えながら判定させて、読み取れる率と中身を表示する
    @Test(arguments: ["prologue_office", "event_furyu", "tokimeki_crossing"])
    func judgesEveryChoice(sceneID: String) async throws {
        let content = try GameContent.loadFromBundle()
        let scene = try #require(content.story.scene(id: sceneID))
        let script = try #require(content.script(for: sceneID))
        print("==== [\(Self.modelID.components(separatedBy: "/").last ?? "")] 判定: \(scene.location)")

        var lines: [DialogueLine] = []
        var readable = 0
        var total = 0
        for beat in script.beats {
            switch beat {
            case .narration(let text):
                lines.append(DialogueLine(speaker: nil, text: text))
            case .line(let line):
                lines.append(DialogueLine(speaker: content.heroine.name, text: line.text))
            case .speech(let speech):
                lines.append(DialogueLine(speaker: speech.displayName, text: speech.text))
            case .choice(let options):
                for option in options {
                    for mood in [Mood.cheerful, .tired] {
                        let request = JudgeRequest(
                            heroine: content.heroine, scene: scene, mood: mood, feelings: Feelings(),
                            recentLines: Array(lines.suffix(8)), playerLine: option.text, reaction: option.reaction.text
                        )
                        let start = Date()
                        let raw = try await Self.judge.judge(request)
                        let parsed = JudgmentParser.parse(raw)
                        total += 1
                        if parsed != nil { readable += 1 }
                        print(String(format: "  [%@] %@ → %@  (%.1fs)%@", mood.label, option.text, raw.replacingOccurrences(of: "\n", with: " "),
                                     Date().timeIntervalSince(start), parsed == nil ? "  ※読めない" : ""))
                    }
                }
                if let first = options.first {
                    lines.append(DialogueLine(speaker: GameConstants.playerName, text: first.text))
                    lines.append(DialogueLine(speaker: content.heroine.name, text: first.reaction.text))
                }
            case .enter, .exit:
                // 立ち絵の出入りは判定に関係ない
                break
            }
        }
        print("  読み取れた判定: \(readable)/\(total)")
        #expect(readable * 10 >= total * 8, "判定の8割以上は読み取れること")
    }
}
