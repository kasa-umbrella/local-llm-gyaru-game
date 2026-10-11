import Foundation

/// LLM が提案した好感度変化を、ヒロインの相性表で補正してクランプする
nonisolated struct AffectionEngine: Sendable {
    static let suggestedRange = -3...3
    static let perTurnRange = -5...5

    func delta(for choice: ChoiceOption, heroine: Heroine) -> Int {
        let suggested = choice.suggestedDelta.clamped(to: Self.suggestedRange)
        return (suggested + heroine.preference(for: choice.tone)).clamped(to: Self.perTurnRange)
    }

    func apply(_ delta: Int, to current: Int) -> Int {
        (current + delta).clamped(to: GameConstants.affectionRange)
    }

    static func relationLabel(for affection: Int) -> String {
        switch affection {
        case 80...: "特別な人"
        case 60..<80: "好きな人"
        case 40..<60: "気になる人"
        case 20..<40: "友達"
        default: "知り合い"
        }
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
