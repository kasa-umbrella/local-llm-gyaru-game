import SwiftUI

/// ノベルゲーム UI の見た目とサイズの定義。
/// 「同じ役割の箱は常に同じ大きさ」にするため、サイズはすべてここで決めて各 View からは参照だけする。
enum NovelTheme {
    // MARK: - 色

    static let panelFill = Color(hex: "#15132A").opacity(0.82)
    static let panelHighlight = Color(hex: "#2A2650").opacity(0.92)
    static let panelBorder = Color.white.opacity(0.55)
    static let panelInnerBorder = Color.white.opacity(0.18)
    static let text = Color.white
    static let subText = Color.white.opacity(0.7)
    static let accent = Color(hex: "#FFC86B")

    // MARK: - 書体

    /// 本文・UI 共通の丸ゴシック。見つからない環境ではシステムの丸ゴシックにフォールバックする
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("HiraMaruProN-W4", size: size, relativeTo: .body)
            .weight(bold ? .bold : .regular)
    }

    // MARK: - サイズ

    struct Metrics {
        let isCompact: Bool

        var screenPadding: CGFloat { isCompact ? 12 : 24 }

        // テキストウィンドウ（行数に関係なく固定）
        var windowHeight: CGFloat { isCompact ? 188 : 210 }
        var windowMaxWidth: CGFloat { 1120 }
        var bodyFontSize: CGFloat { isCompact ? 17 : 21 }
        var bodyLineSpacing: CGFloat { isCompact ? 5 : 7 }
        var bodyLineLimit: Int { 4 }

        // 名前プレート
        var namePlateSize: CGSize { isCompact ? CGSize(width: 148, height: 34) : CGSize(width: 200, height: 40) }
        var nameFontSize: CGFloat { isCompact ? 16 : 19 }

        // クイックメニュー
        var quickButtonSize: CGSize { isCompact ? CGSize(width: 58, height: 26) : CGSize(width: 76, height: 28) }

        // 選択肢
        var choiceSize: CGSize { isCompact ? CGSize(width: 340, height: 50) : CGSize(width: 620, height: 58) }
        var choiceFontSize: CGFloat { isCompact ? 16 : 20 }

        // 章プレート
        var chapterPlateSize: CGSize { isCompact ? CGSize(width: 220, height: 32) : CGSize(width: 300, height: 36) }

        // タイトル・エンディングのボタン
        var menuButtonSize: CGSize { CGSize(width: 260, height: 52) }

        // ヒロイン選択カード
        var heroineCardSize: CGSize { isCompact ? CGSize(width: 340, height: 132) : CGSize(width: 270, height: 400) }
    }
}

// MARK: - 共通パーツ

extension View {
    /// 濃紺の半透明パネル＋二重の枠線。テキストウィンドウ・選択肢・メニューで共通
    func novelPanel(cornerRadius: CGFloat = 10, highlighted: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(highlighted ? NovelTheme.panelHighlight : NovelTheme.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(NovelTheme.panelBorder, lineWidth: 1.5)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: max(cornerRadius - 4, 2))
                        .strokeBorder(NovelTheme.panelInnerBorder, lineWidth: 1)
                        .padding(4)
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
    }

    /// 背景に負けないよう文字に縁取りを付ける
    func novelTextOutline() -> some View {
        shadow(color: .black.opacity(0.85), radius: 0, x: 1, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 1.5)
    }
}

/// 固定サイズのパネル型ボタン。ホバー・押下で少し明るくなる
struct NovelButtonStyle: ButtonStyle {
    let size: CGSize
    var fontSize: CGFloat = 18
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        NovelButtonBody(configuration: configuration, size: size, fontSize: fontSize, cornerRadius: cornerRadius)
    }

    private struct NovelButtonBody: View {
        let configuration: Configuration
        let size: CGSize
        let fontSize: CGFloat
        let cornerRadius: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(NovelTheme.font(fontSize))
                .foregroundStyle(isEnabled ? NovelTheme.text : NovelTheme.subText.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 16)
                .frame(width: size.width, height: size.height)
                .novelPanel(cornerRadius: cornerRadius, highlighted: isEnabled && (isHovered || configuration.isPressed))
                .overlay(alignment: .leading) {
                    if isEnabled && (isHovered || configuration.isPressed) {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(NovelTheme.accent)
                            .padding(.leading, 14)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(.rect(cornerRadius: cornerRadius))
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
}

/// クイックメニュー用の小さな文字ボタン（枠なし）
struct QuickMenuButtonStyle: ButtonStyle {
    let size: CGSize
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NovelTheme.font(size.height * 0.5))
            .foregroundStyle(isOn ? NovelTheme.accent : NovelTheme.subText)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .lineLimit(1)
            .frame(width: size.width, height: size.height)
            .contentShape(.rect)
    }
}
