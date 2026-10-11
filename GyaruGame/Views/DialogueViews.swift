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
        case none, waiting, next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(NovelTheme.font(metrics.bodyFontSize))
                .lineSpacing(metrics.bodyLineSpacing)
                .lineLimit(metrics.bodyLineLimit)
                .minimumScaleFactor(0.8)
                .novelTextOutline()
                .padding(.leading, isNarration ? 12 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 0) {
                indicatorView
                Spacer(minLength: 8)
                quickMenu
            }
        }
        .padding(.top, metrics.namePlateSize.height * 0.5 + 14)
        .padding(.horizontal, metrics.isCompact ? 18 : 32)
        .padding(.bottom, 10)
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
        case .waiting:
            ProgressView()
                .controlSize(.small)
                .tint(NovelTheme.subText)
                .frame(width: 16, height: 16)
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
            .minimumScaleFactor(0.6)
            .novelTextOutline()
            .padding(.horizontal, 12)
            .frame(width: metrics.namePlateSize.width, height: metrics.namePlateSize.height)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [color.mix(with: .black, by: 0.15), color.mix(with: .black, by: 0.45)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            }
    }
}

/// 選択肢。すべて同じ幅・高さの横長バー
struct ChoiceList: View {
    let metrics: NovelTheme.Metrics
    let choices: [ChoiceOption]
    let onSelect: (ChoiceOption) -> Void

    var body: some View {
        VStack(spacing: metrics.isCompact ? 12 : 16) {
            ForEach(choices) { choice in
                Button(choice.text) { onSelect(choice) }
                    .buttonStyle(NovelButtonStyle(size: metrics.choiceSize, fontSize: metrics.choiceFontSize))
            }
        }
    }
}

/// 開発用の好感度表示（DEBUG ビルドのみ）
struct DebugAffectionLabel: View {
    let affection: Int
    let delta: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text("好感度 \(affection)")
            Text(AffectionEngine.relationLabel(for: affection))
            if let delta, delta != 0 {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .foregroundStyle(delta > 0 ? NovelTheme.accent : .cyan)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
    }
}
