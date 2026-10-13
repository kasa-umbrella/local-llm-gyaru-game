import Observation
import SwiftUI

/// 1文字ずつ表示する文字送り。
/// 生成中に本文が伸びた場合は、表示済みの位置を保ったまま続きを送る。
@Observable
final class Typewriter {
    private(set) var text = ""
    private(set) var visibleCount = 0
    var charactersPerSecond: Double = 40

    private var key: Int?
    private var task: Task<Void, Never>?

    var isTyping: Bool {
        visibleCount < text.count
    }

    /// 同じ key のまま本文が伸びたときは続きから、key が変わったら最初から送る
    func show(_ newText: String, key newKey: Int, instant: Bool) {
        if newKey == key, newText.hasPrefix(text) {
            text = newText
        } else {
            key = newKey
            text = newText
            visibleCount = 0
        }
        if instant {
            visibleCount = text.count
        }
        startIfNeeded()
    }

    func complete() {
        visibleCount = text.count
    }

    /// 未表示の部分は透明にして描画し、改行位置がずれないようにする
    func attributedText(color: Color) -> AttributedString {
        var visible = AttributedString(String(text.prefix(visibleCount)))
        visible.foregroundColor = color
        var hidden = AttributedString(String(text.dropFirst(visibleCount)))
        hidden.foregroundColor = .clear
        return visible + hidden
    }

    private func startIfNeeded() {
        guard task == nil, isTyping else { return }
        task = Task { [weak self] in
            while let self, self.isTyping, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1 / self.charactersPerSecond))
                self.visibleCount = min(self.visibleCount + 1, self.text.count)
            }
            self?.task = nil
        }
    }
}

/// 画面下部のテキストウィンドウ。本文の長さに関係なく常に同じ大きさ
struct DialogueWindow: View {
    let metrics: NovelTheme.Metrics
    let speaker: String?
    let speakerColor: Color
    let text: AttributedString
    let isNarration: Bool
    let indicator: Indicator
    let isAutoOn: Bool
    let isSkipOn: Bool
    let onAdvance: () -> Void
    let onLog: () -> Void
    let onAuto: () -> Void
    let onSkip: () -> Void
    let onTitle: () -> Void

    enum Indicator {
        case none, next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(NovelTheme.font(metrics.bodyFontSize))
                .lineSpacing(metrics.bodyLineSpacing)
                .lineLimit(metrics.bodyLineLimit)
                .minimumScaleFactor(NovelTheme.minimumScale(for: metrics.bodyFontSize))
                .padding(.leading, isNarration ? 12 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 0) {
                indicatorView
                Spacer(minLength: 8)
                quickMenu
            }
        }
        .padding(.top, metrics.windowTopInset)
        .padding(.horizontal, metrics.windowHorizontalPadding)
        .padding(.bottom, metrics.windowBottomInset)
        .frame(maxWidth: metrics.windowMaxWidth)
        .frame(height: metrics.windowHeight)
        .novelPanel(cornerRadius: 14)
        .overlay(alignment: .topLeading) {
            if let speaker {
                NamePlate(metrics: metrics, name: speaker, color: speakerColor)
                    .offset(x: metrics.isCompact ? 14 : 28, y: -metrics.namePlateSize.height * 0.5)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onAdvance)
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .none:
            Color.clear.frame(width: 16, height: 16)
        case .next:
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 12))
                .foregroundStyle(NovelTheme.accent)
                .symbolEffect(.bounce, options: .repeating.speed(0.6))
                .frame(width: 16, height: 16)
        }
    }

    private var quickMenu: some View {
        HStack(spacing: 2) {
            Button("ログ", action: onLog)
                .buttonStyle(QuickMenuButtonStyle(size: metrics.quickButtonSize))
            Button("オート", action: onAuto)
                .buttonStyle(QuickMenuButtonStyle(size: metrics.quickButtonSize, isOn: isAutoOn))
            Button("スキップ", action: onSkip)
                .buttonStyle(QuickMenuButtonStyle(size: metrics.quickButtonSize, isOn: isSkipOn))
            Button("タイトル", action: onTitle)
                .buttonStyle(QuickMenuButtonStyle(size: metrics.quickButtonSize))
        }
    }
}

/// テキストウィンドウの左上に食い込む名前プレート。名前の長さに関係なく同じ大きさ
struct NamePlate: View {
    let metrics: NovelTheme.Metrics
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(NovelTheme.font(metrics.nameFontSize, bold: true))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(NovelTheme.minimumScale(for: metrics.nameFontSize))
            .padding(.horizontal, 12)
            .frame(width: metrics.namePlateSize.width, height: metrics.namePlateSize.height)
            .background(color.mix(with: .black, by: 0.35), in: .rect(cornerRadius: 8))
    }
}

/// 選択肢。すべて同じ幅・高さの横長バー
struct ChoiceList: View {
    let metrics: NovelTheme.Metrics
    let choices: [ChoiceOption]
    let onSelect: (ChoiceOption) -> Void

    var body: some View {
        VStack(spacing: metrics.choiceSpacing) {
            ForEach(choices) { choice in
                Button(choice.text) { onSelect(choice) }
                    .buttonStyle(NovelButtonStyle(size: metrics.choiceSize, fontSize: metrics.choiceFontSize))
            }
        }
    }
}

/// 開発用のパラメータ表示（DEBUG ビルドのみ）。気分と3つの軸を、同じ大きさの別々の箱に出す
struct DebugStatsRow: View {
    let metrics: NovelTheme.Metrics
    /// 1段に並べる箱の数（4なら1段、2なら2段）
    let columns: Int
    let feelings: Feelings
    let delta: Feelings?
    let mood: Mood

    private static let labelText = Color(white: 0.2)
    private static let valueFill = Color.white

    var body: some View {
        Grid(horizontalSpacing: metrics.debugStatSpacing, verticalSpacing: metrics.debugStatSpacing) {
            ForEach(Array(stats.chunked(by: columns).enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.title) { stat in
                        box(stat)
                    }
                }
            }
        }
    }

    private struct Stat {
        let title: String
        let icon: String
        let color: Color
        let value: String
        let change: Int
    }

    private var stats: [Stat] {
        [Stat(title: "気分", icon: "face.smiling", color: Color(hex: "#F6E3A1"), value: mood.label, change: 0)]
            + Axis.allCases.map { axis in
                Stat(title: axis.label, icon: axis.iconName, color: axis.color, value: "\(feelings[axis])", change: delta?[axis] ?? 0)
            }
    }

    private func box(_ stat: Stat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: stat.icon)
                Text(stat.title)
            }
            .font(NovelTheme.font(NovelTheme.minimumFontSize, bold: true))
            .foregroundStyle(Self.labelText)
            .padding(.leading, 8)
            .frame(width: metrics.debugStatLabelWidth, height: metrics.debugStatSize.height, alignment: .leading)
            .background(stat.color)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // 直前の判定で動いた分。動かなかった軸は何も出さない
                if stat.change != 0 {
                    Text(stat.change > 0 ? "+\(stat.change)" : "\(stat.change)")
                        .font(.system(size: NovelTheme.minimumFontSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(stat.change > 0 ? Color(hex: "#D9485F") : Color(hex: "#2F7FB8"))
                }
                Spacer(minLength: 0)
                Text(stat.value)
                    .font(stat.title == "気分"
                        ? NovelTheme.font(NovelTheme.minimumFontSize, bold: true)
                        : .system(size: metrics.debugStatValueFontSize, weight: .medium).monospacedDigit())
                    .foregroundStyle(Self.labelText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.valueFill)
        }
        .frame(width: metrics.debugStatSize.width, height: metrics.debugStatSize.height)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// 選んだ選択肢でひよりの気持ちが動いた軸を、立ち絵の上にふわっと出して消す。数字は出さず、矢印の数で強さを表す
struct FeelingFeedbackView: View {
    let metrics: NovelTheme.Metrics
    let feedback: FeelingFeedback?

    /// 出ている時間
    private static let visibleDuration: Duration = .seconds(1.6)
    private static let downFill = Color(white: 0.15).opacity(0.85)
    private static let labelText = Color(white: 0.2)

    @State private var shown: FeelingFeedback?

    var body: some View {
        HStack(spacing: 8) {
            if let shown {
                ForEach(shown.changes, id: \.axis) { change in
                    chip(axis: change.axis, delta: change.delta)
                }
            }
        }
        .opacity(shown == nil ? 0 : 1)
        .offset(y: shown == nil ? 8 : 0)
        .animation(.easeOut(duration: 0.3), value: shown)
        .task(id: feedback) {
            guard let feedback else { return }
            shown = feedback
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            shown = nil
        }
        .allowsHitTesting(false)
    }

    private func chip(axis: Axis, delta: Int) -> some View {
        let isUp = delta > 0
        return HStack(spacing: 4) {
            Image(systemName: axis.iconName)
                .foregroundStyle(isUp ? Self.labelText : axis.color)
            Text(String(repeating: isUp ? "↑" : "↓", count: abs(delta)))
                .foregroundStyle(isUp ? Self.labelText : NovelTheme.text)
        }
        .font(.system(size: metrics.feedbackFontSize, weight: .bold))
        .frame(width: metrics.feedbackChipSize.width, height: metrics.feedbackChipSize.height)
        .background(isUp ? axis.color : Self.downFill, in: .capsule)
        .accessibilityLabel("\(axis.label)が\(isUp ? "上がった" : "下がった")")
    }
}
