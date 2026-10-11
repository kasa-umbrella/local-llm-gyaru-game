import SwiftUI

/// 「はじめから」の後に、ルートを進めるヒロインを1人選ぶ画面
struct HeroineSelectView: View {
    @Environment(GameViewModel.self) private var game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        ZStack {
            SceneBackgroundView(name: "office_building_night")
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("誰と過ごす？")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("選んだ相手との物語が始まります")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 8)

                    GlassEffectContainer(spacing: 20) {
                        let layout = isCompact
                            ? AnyLayout(VStackLayout(spacing: 16))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                        layout {
                            ForEach(game.content.heroines) { heroine in
                                HeroineCard(heroine: heroine, isCompact: isCompact) {
                                    game.newGame(heroineID: heroine.id)
                                }
                            }
                        }
                    }

                    Button("タイトルへ戻る", systemImage: "chevron.backward", action: game.returnToTitle)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(isCompact ? 16 : 40)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct HeroineCard: View {
    let heroine: Heroine
    let isCompact: Bool
    let onSelect: () -> Void

    private var themeColor: Color {
        Color(hex: heroine.themeColor)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                HeroinePortrait(heroine: heroine, size: isCompact ? 96 : 140)
                Text(heroine.name)
                    .font(.title2.bold())
                Text(heroine.role)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(themeColor)
                Text(heroine.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: isCompact ? .infinity : 280)
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(themeColor.opacity(0.2)).interactive(), in: .rect(cornerRadius: 28))
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
                Image(systemName: "figure.stand.dress")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(color.gradient)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.opacity(0.18))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(color.opacity(0.6), lineWidth: 2))
    }
}
