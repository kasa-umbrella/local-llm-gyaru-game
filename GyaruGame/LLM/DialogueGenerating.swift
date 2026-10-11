import Foundation

/// 画面に出す1行。speaker が nil なら地の文
nonisolated struct DialogueLine: Equatable, Sendable {
    var speaker: String?
    var text: String
    var emotion: Emotion = .normal
}

nonisolated struct ChoiceOption: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    let tone: ChoiceTone
    /// LLM が提案した好感度変化（AffectionEngine が補正する前の値）
    let suggestedDelta: Int
}

/// ストリーミング中の途中結果。isFinal が true のときだけ choices が埋まる
nonisolated struct TurnDraft: Sendable {
    var lines: [DialogueLine]
    var choices: [ChoiceOption]
    var isFinal: Bool
}

nonisolated struct LogEntry: Equatable, Sendable {
    let speaker: String
    let text: String
}

nonisolated struct TurnRequest: Sendable {
    let heroine: Heroine
    let directive: SceneDirective
    let affection: Int
    let summaries: [String]
    let recentLog: [LogEntry]
    let lore: [LoreEntry]
    let lastChoice: String?
}

nonisolated struct SummaryRequest: Sendable {
    let heroine: Heroine
    let directive: SceneDirective
    let log: [LogEntry]
}

/// LLM 層の抽象。Foundation Models 実装とモック実装を差し替えられるようにする
protocol DialogueGenerating: AnyObject {
    func prewarm(for heroine: Heroine)
    func streamTurn(_ request: TurnRequest) -> AsyncThrowingStream<TurnDraft, Error>
    func summarize(_ request: SummaryRequest) async throws -> String
}
