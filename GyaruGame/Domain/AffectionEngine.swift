import Foundation

/// 好感度の変化量 = 返答の方向性ごとの基準値 + ヒロインの相性表 + LLM の判定（微調整）。
/// オンデバイスモデルの判定はほぼ同じ値しか返さないため、主役は基準値と相性表にして、
/// LLM の判定は ±1 の範囲でだけ効かせる。
nonisolated struct AffectionEngine: Sendable {
    static let llmAdjustmentRange = -1...1
    static let perTurnRange = -5...5

    static func baseDelta(for tone: ChoiceTone) -> Int {
        switch tone {
        case .kind, .honest: 2
        case .teasing, .romantic: 1
        case .cool: -1
        case .rude: -3
        }
    }

    func delta(for choice: ChoiceOption, heroine: Heroine) -> Int {
        let adjustment = choice.suggestedDelta.clamped(to: Self.llmAdjustmentRange)
        return (Self.baseDelta(for: choice.tone) + heroine.preference(for: choice.tone) + adjustment)
            .clamped(to: Self.perTurnRange)
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
