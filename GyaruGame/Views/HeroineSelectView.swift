import SwiftUI

/// 「はじめから」の後に、ルートを進めるヒロインを1人選ぶ画面
struct HeroineSelectView: View {
    @Environment(GameViewModel.self) private var game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var metrics: NovelTheme.Metrics {
        NovelTheme.Metrics(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    var body: some View {
        ZStack {
            SceneBackgroundView(name: "office_building_night")
                .ignoresSafeArea()
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: metrics.isCompact ? 20 : 32) {
                    Text("ヒロイン選択")
                        .font(NovelTheme.font(metrics.isCompact ? 22 : 28, bold: true))
                        .foregroundStyle(.white)
                        .novelTextOutline()

                    let layout = metrics.isCompact
                        ? AnyLayout(VStackLayout(spacing: 14))
                        : AnyLayout(HStackLayout(spacing: 24))
                    layout {
                        ForEach(game.content.heroines) { heroine in
                            Button {
                                game.newGame(heroineID: heroine.id)
                            } label: {
                                HeroineCard(heroine: heroine, metrics: metrics)
                            }
                            .buttonStyle(HeroineCardButtonStyle(size: metrics.heroineCardSize))
                        }
                    }

                    Button("戻る", action: game.returnToTitle)
                        .buttonStyle(NovelButtonStyle(size: CGSize(width: 160, height: 44), fontSize: 16))
                }
                .padding(metrics.screenPadding)
                .padding(.vertical, metrics.isCompact ? 8 : 24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// 選択カードの中身。紹介文の長さに関係なくカードの大きさは同じ
private struct HeroineCard: View {
    let heroine: Heroine
    let metrics: NovelTheme.Metrics

    var body: some View {
        let color = Color(hex: heroine.themeColor)
        if metrics.isCompact {
            HStack(spacing: 16) {
                HeroinePortrait(heroine: heroine, size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    nameBlock(color: color)
                    tagline(lines: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
        } else {
            VStack(spacing: 14) {
                HeroinePortrait(heroine: heroine, size: 150)
                    .padding(.top, 28)
                nameBlock(color: color)
                tagline(lines: 4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                Spacer(minLength: 0)
            }
        }
    }

    private func nameBlock(color: Color) -> some View {
        VStack(alignment: metrics.isCompact ? .leading : .center, spacing: 4) {
            Text(heroine.role)
                .font(NovelTheme.font(NovelTheme.minimumFontSize))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(color.mix(with: .black, by: 0.35), in: .rect(cornerRadius: 4))
            Text(heroine.name)
                .font(NovelTheme.font(metrics.isCompact ? 20 : 24, bold: true))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private func tagline(lines: Int) -> some View {
        Text(heroine.tagline)
            .font(NovelTheme.font(metrics.isCompact ? 13 : 14))
            .foregroundStyle(NovelTheme.subText)
            .lineSpacing(3)
            .lineLimit(lines)
    }
}

private struct HeroineCardButtonStyle: ButtonStyle {
    let size: CGSize

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, size: size)
    }

    private struct CardBody: View {
        let configuration: Configuration
        let size: CGSize
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(width: size.width, height: size.height)
                .novelPanel(cornerRadius: 14, highlighted: isHovered || configuration.isPressed)
                .contentShape(.rect(cornerRadius: 14))
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
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
