import SwiftUI

/// ノベルゲーム UI の見た目とサイズの定義。
/// 「同じ役割の箱は常に同じ大きさ」にするため、サイズはすべてここで決めて各 View からは参照だけする。
enum NovelTheme {
    // MARK: - 色

    static let panelFill = Color.black.opacity(0.62)
    static let panelHighlight = Color(white: 0.22).opacity(0.82)
    /// 背景画像がないときの下地
    static let placeholderBackground = Color(white: 0.16)
    static let text = Color.white
    static let subText = Color.white.opacity(0.7)
    static let accent = Color(hex: "#FFC86B")

    // MARK: - 書体

    /// 本文・UI 共通の丸ゴシック。見つからない環境ではシステムの丸ゴシックにフォールバックする
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("HiraMaruProN-W4", size: size, relativeTo: .body)
            .weight(bold ? .bold : .regular)
    }

    /// これより小さい文字は出さない（縮小表示の下限にも使う）
    static let minimumFontSize: CGFloat = 13

    /// 縮小しても minimumFontSize を下回らない minimumScaleFactor
    static func minimumScale(for fontSize: CGFloat) -> CGFloat {
        min(1, minimumFontSize / fontSize)
    }

    // MARK: - サイズ

    /// 画面の大きさごとの寸法。値は3段階だけで、同じ画面の中では常に同じサイズになる
    /// - isCompact: 横幅が狭い（iPhone の縦画面など）
    /// - isShort: 高さが足りない（iPhone の横画面など）
    struct Metrics {
        let isCompact: Bool
        let isShort: Bool

        init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
            isCompact = horizontal == .compact
            isShort = vertical == .compact
        }

        private func pick<T>(short: T, compact: T, regular: T) -> T {
            isShort ? short : (isCompact ? compact : regular)
        }

        var screenPadding: CGFloat { pick(short: 8, compact: 12, regular: 24) }

        // テキストウィンドウ（行数に関係なく固定）
        // 高さは 上の余白 + 本文 bodyLineLimit 行 + クイックメニュー + 下の余白に、少しゆとりを足したもの。
        // 本文の1行はヒラギノ丸ゴで 15pt → 23, 21pt → 32。iPhone 縦は1行に18字ほどしか入らないので4行のまま
        var windowHeight: CGFloat { pick(short: 116, compact: 200, regular: 184) }
        var windowMaxWidth: CGFloat { 1120 }
        var windowHorizontalPadding: CGFloat { pick(short: 28, compact: 24, regular: 44) }
        /// 名前プレートの下端から本文までの余白を含めた上の余白
        var windowTopInset: CGFloat { namePlateSize.height * 0.5 + pick(short: 12, compact: 20, regular: 24) }
        var windowBottomInset: CGFloat { pick(short: 8, compact: 12, regular: 14) }
        var bodyFontSize: CGFloat { pick(short: 15, compact: 17, regular: 21) }
        var bodyLineSpacing: CGFloat { pick(short: 2, compact: 5, regular: 7) }
        var bodyLineLimit: Int { pick(short: 2, compact: 4, regular: 2) }

        // 名前プレート
        var namePlateSize: CGSize {
            pick(short: CGSize(width: 136, height: 28), compact: CGSize(width: 148, height: 34), regular: CGSize(width: 200, height: 40))
        }
        var nameFontSize: CGFloat { pick(short: 14, compact: 16, regular: 19) }

        // クイックメニュー
        var quickButtonSize: CGSize {
            pick(short: CGSize(width: 64, height: 22), compact: CGSize(width: 58, height: 26), regular: CGSize(width: 76, height: 28))
        }

        // 選択肢
        var choiceSize: CGSize {
            pick(short: CGSize(width: 460, height: 40), compact: CGSize(width: 340, height: 50), regular: CGSize(width: 620, height: 58))
        }
        var choiceFontSize: CGFloat { pick(short: 15, compact: 16, regular: 20) }
        var choiceSpacing: CGFloat { pick(short: 8, compact: 12, regular: 16) }

        // 章プレート
        var chapterPlateSize: CGSize {
            pick(short: CGSize(width: 200, height: 28), compact: CGSize(width: 220, height: 32), regular: CGSize(width: 300, height: 36))
        }
        var chapterFontSize: CGFloat { pick(short: 13, compact: 13, regular: 15) }

        // 開発用のパラメータ表示（気分・3軸がそれぞれ同じ大きさの箱。左が色付きの項目名、右が白地の値）
        var debugStatSize: CGSize {
            pick(short: CGSize(width: 156, height: 26), compact: CGSize(width: 168, height: 30), regular: CGSize(width: 180, height: 32))
        }
        /// 項目名の部分の幅（残りが値の部分）
        var debugStatLabelWidth: CGFloat { pick(short: 84, compact: 88, regular: 92) }
        var debugStatValueFontSize: CGFloat { pick(short: 15, compact: 16, regular: 18) }
        var debugStatSpacing: CGFloat { pick(short: 6, compact: 8, regular: 8) }

        // タイトル・エンディングのボタン
        var menuButtonSize: CGSize { isShort ? CGSize(width: 240, height: 44) : CGSize(width: 260, height: 52) }

        // エンディングの枠
        var endingWindowSize: CGSize {
            pick(short: CGSize(width: 560, height: 300), compact: CGSize(width: 340, height: 400), regular: CGSize(width: 600, height: 400))
        }

        // ヒロイン選択カード
        var heroineCardSize: CGSize { isCompact ? CGSize(width: 340, height: 132) : CGSize(width: 270, height: 400) }
    }
}

// MARK: - 共通パーツ

extension View {
    /// 濃紺の半透明パネル。区切りは塗りだけで作り、枠線と影は付けない
    func novelPanel(cornerRadius: CGFloat = 10, highlighted: Bool = false) -> some View {
        background(
            highlighted ? NovelTheme.panelHighlight : NovelTheme.panelFill,
            in: .rect(cornerRadius: cornerRadius)
        )
    }

    /// 写真の背景の上に直接乗る文字だけに付ける縁取り（パネルの中の文字には付けない）
    func novelTextOutline() -> some View {
        shadow(color: .black.opacity(0.85), radius: 0, x: 1, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 1.5)
    }
}

/// 固定サイズのパネル型ボタン。ホバー・押下で少し明るくなる。isSelected なら常に明るく、文字をアクセント色にする
struct NovelButtonStyle: ButtonStyle {
    let size: CGSize
    var fontSize: CGFloat = 18
    var cornerRadius: CGFloat = 10
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        NovelButtonBody(configuration: configuration, size: size, fontSize: fontSize, cornerRadius: cornerRadius, isSelected: isSelected)
    }

    private struct NovelButtonBody: View {
        let configuration: Configuration
        let size: CGSize
        let fontSize: CGFloat
        let cornerRadius: CGFloat
        let isSelected: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(NovelTheme.font(fontSize))
                .foregroundStyle(isSelected ? NovelTheme.accent : (isEnabled ? NovelTheme.text : NovelTheme.subText.opacity(0.6)))
                .lineLimit(1)
                .minimumScaleFactor(NovelTheme.minimumScale(for: fontSize))
                .padding(.horizontal, 16)
                .frame(width: size.width, height: size.height)
                .novelPanel(cornerRadius: cornerRadius, highlighted: isSelected || (isEnabled && (isHovered || configuration.isPressed)))
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
            .font(NovelTheme.font(max(size.height * 0.5, NovelTheme.minimumFontSize)))
            .foregroundStyle(isOn ? NovelTheme.accent : NovelTheme.subText)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .lineLimit(1)
            .frame(width: size.width, height: size.height)
            .contentShape(.rect)
    }
}
