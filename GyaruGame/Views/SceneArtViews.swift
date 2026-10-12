import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// アセットカタログに画像があるときだけ Image を返す（macOS / iOS 共通）
enum AssetImage {
    static func named(_ name: String) -> Image? {
        #if canImport(UIKit)
        UIImage(named: name).map(Image.init(uiImage:))
        #else
        NSImage(named: name).map(Image.init(nsImage:))
        #endif
    }
}

/// 背景。アセット `bg_<name>` があれば表示し、なければ場所ごとのグラデーションで代用する
struct SceneBackgroundView: View {
    let name: String

    var body: some View {
        if let image = AssetImage.named("bg_\(name)") {
            // scaledToFill の画像が親のレイアウトを押し広げないよう、overlay で敷いて切り抜く
            Color.clear
                .overlay {
                    image
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            NovelTheme.placeholderBackground
        }
    }
}

/// 立ち絵。アセット `<heroineID>_<emotion>` → `<heroineID>_normal` の順に探し、なければシルエットで代用する
///
/// 全身絵の上側だけを表示枠の高さに合わせて拡大し、バストアップで見せる。はみ出した分は切り抜く
struct HeroineSpriteView: View {
    let heroine: Heroine
    let emotion: Emotion

    /// 全身絵のうち、表示枠の高さに収める上側の割合。小さいほど寄りになる（1 で全身）
    static let visibleFraction: CGFloat = 0.5
    /// 立ち絵アセットの縦横比（幅 / 高さ）。生成時の 2:3 に合わせている
    private static let spriteAspect: CGFloat = 2.0 / 3.0

    var body: some View {
        if let image = AssetImage.named("\(heroine.id)_\(emotion.rawValue)") ?? AssetImage.named("\(heroine.id)_normal") {
            GeometryReader { proxy in
                let height = proxy.size.height / Self.visibleFraction
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * Self.spriteAspect, height: height)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
            .id(emotion)
            .transition(.opacity)
        } else {
            placeholder
        }
    }

    /// 立ち絵が用意されるまでのシルエット
    private var placeholder: some View {
        Image(systemName: "figure.stand.dress")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 420)
            .foregroundStyle(Color(hex: heroine.themeColor).mix(with: .black, by: 0.2))
            #if DEBUG
            .overlay(alignment: .top) {
                Text(emotion.rawValue)
                    .font(.system(size: NovelTheme.minimumFontSize).monospaced())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
            }
            #endif
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// 丸い顔アイコン。`<heroineID>_normal` があれば切り抜いて使い、なければシルエットで代用する
struct HeroinePortrait: View {
    let heroine: Heroine
    let size: CGFloat

    var body: some View {
        let color = Color(hex: heroine.themeColor)
        Group {
            if let image = AssetImage.named("\(heroine.id)_normal") {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.55))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(y: size * 0.1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.mix(with: .black, by: 0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}
