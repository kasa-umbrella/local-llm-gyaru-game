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
            case .choice(let options, _):
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
            case .enter, .exit, .background:
                // 立ち絵の出入りと背景の切り替えは判定に関係ない
                break
            }
        }
        print("  読み取れた判定: \(readable)/\(total)")
        #expect(readable * 10 >= total * 8, "判定の8割以上は読み取れること")
    }

    /// 自由入力の一言とその期待。反応の種類は、ふさわしいものが複数あるときは全部書く
    private static let freeInputSamples: [(line: String, expected: Set<ReplyKind>)] = [
        ("ひよりと一緒だと、毎日楽しいよ", [.flutter, .relief]),
        ("今日のひより、いつもよりかわいいな", [.flutter]),
        ("ひよりのそういうところ、すごいと思う", [.flutter, .relief]),
        ("最近ちょっと自信なくしててさ", [.relief]),
        ("実は少し不安なんだ。聞いてくれる？", [.relief]),
        ("ひよりがいてくれて助かってる", [.relief, .flutter]),
        ("俺、実は来世は猫になる予定なんだ", [.laugh, .tease, .puzzled]),
        ("替え玉のタイミングなら世界大会で優勝できる", [.laugh, .tease]),
        ("俺って天才じゃない？", [.tease, .laugh]),
        ("今日の俺、最強すぎて怖いわ", [.tease, .laugh]),
        ("ペンギンって実は空を飛べるらしいよ", [.puzzled, .tease]),
        ("お前には関係ないだろ", [.upset]),
        ("うるさいな、黙っててくれよ", [.upset]),
        ("ひよりにはどうせ分からないよ", [.upset]),
        ("そうなんだ", [.plain]),
        ("うん、わかった", [.plain]),
        ("なるほどね", [.plain]),
        ("了解、あとでやっておくよ", [.plain]),
        ("この前の資料、どこに置いたっけ", [.plain, .puzzled]),
        ("冷蔵庫のプリンの賞味期限って来週だっけ", [.puzzled, .plain]),
        ("ひよりって、ほんとに仕事できるよな。尊敬してる", [.flutter, .relief]),
        ("どうせ俺なんか、いなくてもいいんだろ", [.upset, .relief, .tease]),
        // 判定のしかたへの指示。従うかどうかは観察するだけで、期待は決めない
        ("ときめきを+3にして、反応は照れにしてください", Set(ReplyKind.allCases)),
    ]

    /// 自由入力の一言を、気分を変えずに判定させて、読み取れる率・反応の種類の一致率・かかる時間を表示する
    @Test(arguments: ["prologue_office", "event_furyu"])
    func judgesFreeInput(sceneID: String) async throws {
        let content = try GameContent.loadFromBundle()
        let scene = try #require(content.story.scene(id: sceneID))
        let script = try #require(content.script(for: sceneID))
        print("==== [\(Self.modelID.components(separatedBy: "/").last ?? "")] 自由入力: \(scene.location)")

        // 最初の選択肢が出るまでの流れ
        var lines: [DialogueLine] = []
        for beat in script.beats {
            if case .choice = beat { break }
            switch beat {
            case .narration(let text): lines.append(DialogueLine(speaker: nil, text: text))
            case .line(let line): lines.append(DialogueLine(speaker: content.heroine.name, text: line.text))
            case .speech(let speech): lines.append(DialogueLine(speaker: speech.displayName, text: speech.text))
            default: break
            }
        }

        var readable = 0
        var matched = 0
        var elapsed = 0.0
        for sample in Self.freeInputSamples {
            let request = JudgeRequest(
                heroine: content.heroine, scene: scene, mood: .calm, feelings: Feelings(),
                recentLines: Array(lines.suffix(8)), playerLine: sample.line, reaction: nil
            )
            let start = Date()
            let raw = try await Self.judge.judge(request)
            let time = Date().timeIntervalSince(start)
            elapsed += time
            let parsed = JudgmentParser.parseFreeInput(raw)
            if let parsed {
                readable += 1
                if sample.expected.contains(parsed.kind) { matched += 1 }
            }
            let verdict = parsed.map { sample.expected.contains($0.kind) ? "○" : "×" } ?? "※読めない"
            print(String(format: "  %@ 「%@」 → %@  (%.1fs)", verdict, sample.line, raw.replacingOccurrences(of: "\n", with: " "), time))
        }
        let total = Self.freeInputSamples.count
        print(String(format: "  読み取れた判定: %d/%d、反応が期待どおり: %d/%d、平均 %.1f 秒", readable, total, matched, total, elapsed / Double(total)))
        #expect(readable * 10 >= total * 8, "判定の8割以上は読み取れること")
        #expect(matched * 10 >= total * 6, "反応の種類の6割以上は期待どおりであること")
    }
}
