import Foundation
import Testing
@testable import GyaruGame

/// ローカルLLM（Qwen3.5 on MLX）で各シーンのターンを生成できるかの確認。
/// 初回はモデルのダウンロード（約3GB）が走るので、環境変数を付けたときだけ実行する:
/// `TEST_RUNNER_RUN_LOCAL_LLM_TESTS=1 xcodebuild test ...`
/// モデルを変えるときは `TEST_RUNNER_LOCAL_LLM_MODEL=mlx-community/Qwen3.5-9B-MLX-4bit` も付ける。
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_LOCAL_LLM_TESTS"] != nil), .serialized)
struct LocalLLMSmokeTests {
    private static let modelID = ProcessInfo.processInfo.environment["LOCAL_LLM_MODEL"] ?? LocalLLMDialogueGenerator.modelID
    private static let generator = LocalLLMDialogueGenerator(modelID: modelID)

    @Test(.timeLimit(.minutes(30)))
    func preloadsModel() async throws {
        try await Self.generator.preload()
    }

    @Test(arguments: [
        ("hiyori", 0, nil), ("mio", 0, nil), ("ruka", 0, nil),
        ("hiyori", 1, "うまそう、いただきます"), ("mio", 1, "最後まで読んだよ、面白かった"), ("ruka", 1, "今日はとことん付き合うよ"),
    ] as [(String, Int, String?)])
    func generatesTurn(heroineID: String, chapterIndex: Int, lastChoice: String?) async throws {
        let content = try GameContent.loadFromBundle()
        let director = StoryDirector(chapters: content.chapters)
        let progress = GameProgress(heroineID: heroineID, chapterIndex: chapterIndex, turnInScene: lastChoice == nil ? 0 : 1)
        let directive = try #require(director.directive(for: progress))
        let heroine = try #require(content.heroine(id: heroineID))

        let request = TurnRequest(
            heroine: heroine, directive: directive, affection: lastChoice == nil ? 0 : 35,
            summaries: [], recentLog: [],
            lore: LoreRetriever(entries: content.lore).retrieve(
                heroineID: heroine.id, sceneTags: directive.scene.tags, recentText: lastChoice ?? ""
            ),
            lastChoice: lastChoice
        )

        let start = Date()
        var final: TurnDraft?
        for try await draft in Self.generator.streamTurn(request) where draft.isFinal {
            final = draft
        }
        let turn = try #require(final)
        #expect(!turn.lines.isEmpty)
        #expect(turn.choices.count == 3)

        print("---- [\(Self.modelID.components(separatedBy: "/").last ?? "")] \(heroine.name) / \(directive.scene.location)\(lastChoice.map { " ←「\($0)」" } ?? "") (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)")
        turn.lines.forEach { print("[\($0.emotion)] \($0.text)") }
        turn.choices.forEach { print("  > \($0.text) (\($0.tone), \($0.suggestedDelta))") }
    }
}
