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
            LinearGradient(colors: Self.placeholderColors(for: name), startPoint: .top, endPoint: .bottom)
        }
    }

    private static func placeholderColors(for name: String) -> [Color] {
        switch name {
        case "bookcafe": [Color(hex: "#5B4636"), Color(hex: "#2E2219")]
        case "rooftop": [Color(hex: "#8FD3FF"), Color(hex: "#E8F6FF")]
        case "izakaya": [Color(hex: "#E0803C"), Color(hex: "#4A1F12")]
        case "festival": [Color(hex: "#1B1446"), Color(hex: "#C2185B")]
        case "hill_night": [Color(hex: "#0B1033"), Color(hex: "#3A2C6B")]
        default: [Color(hex: "#444444"), Color(hex: "#111111")]
        }
    }
}

/// 立ち絵。アセット `<heroineID>_<emotion>` → `<heroineID>_normal` の順に探し、なければシルエットで代用する
struct HeroineSpriteView: View {
    let heroine: Heroine
    let emotion: Emotion

    var body: some View {
        if let image = AssetImage.named("\(heroine.id)_\(emotion.rawValue)") ?? AssetImage.named("\(heroine.id)_normal") {
            image
                .resizable()
                .scaledToFit()
                .id(emotion)
                .transition(.opacity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: emotion.symbolName)
                .font(.system(size: 64))
                .contentTransition(.symbolEffect(.replace))
            Image(systemName: "figure.stand.dress")
                .font(.system(size: 220))
                .minimumScaleFactor(0.4)
            Text(heroine.name)
                .font(.title2.bold())
        }
        .foregroundStyle(Color(hex: heroine.themeColor).gradient)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

extension Emotion {
    var symbolName: String {
        switch self {
        case .normal: "face.smiling"
        case .smile: "face.smiling.inverse"
        case .shy: "heart.circle"
        case .angry: "flame"
        case .sad: "cloud.rain"
        case .surprised: "exclamationmark.circle"
        }
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
