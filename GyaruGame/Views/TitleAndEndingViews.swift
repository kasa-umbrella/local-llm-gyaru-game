import SwiftUI

struct ContentView: View {
    @Environment(GameViewModel.self) private var game

    var body: some View {
        Group {
            switch game.screen {
            case .title:
                TitleView()
            case .heroineSelect:
                HeroineSelectView()
            case .playing:
                GameView()
            case .ending(let ending):
                EndingView(ending: ending)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: game.screen)
    }
}

struct TitleView: View {
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

            VStack(spacing: 0) {
                Spacer()
                Text("定時後ローカルLLM")
                    .font(NovelTheme.font(metrics.isCompact ? 36 : 60, bold: true))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .novelTextOutline()
                    .padding(.horizontal, metrics.screenPadding)
                Spacer()

                VStack(spacing: 14) {
                    Button("はじめから", action: game.showHeroineSelect)
                        .disabled(!game.isBackendReady)
                    Button("つづきから", action: game.continueGame)
                        .disabled(!game.hasContinuableSave || !game.isBackendReady)
                }
                .buttonStyle(NovelButtonStyle(size: metrics.menuButtonSize, fontSize: 19))

                EngineSelector()
                    .padding(.top, metrics.isShort ? 14 : 28)
                    .padding(.bottom, metrics.screenPadding + 12)
            }
        }
    }
}

struct EndingView: View {
    @Environment(GameViewModel.self) private var game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let ending: Ending

    private var metrics: NovelTheme.Metrics {
        NovelTheme.Metrics(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    private var heroine: Heroine? {
        game.content.heroine(id: ending.heroineID)
    }

    var body: some View {
        ZStack {
            SceneBackgroundView(name: ending.kind == .good ? "hill_night" : "riverside_evening")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if let heroine {
                    HeroinePortrait(heroine: heroine, size: 104)
                }
                Text(title)
                    .font(NovelTheme.font(metrics.isCompact ? 28 : 36, bold: true))
                    .foregroundStyle(NovelTheme.accent)
                Text(message)
                    .font(NovelTheme.font(metrics.isCompact ? 15 : 18))
                    .foregroundStyle(NovelTheme.text)
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity)
                Button("タイトルへ", action: game.returnToTitle)
                    .buttonStyle(NovelButtonStyle(size: metrics.menuButtonSize, fontSize: 18))
            }
            .padding(28)
            .frame(width: metrics.endingWindowSize.width, height: metrics.endingWindowSize.height)
            .novelPanel(cornerRadius: 16)
        }
    }

    private var title: String {
        switch ending.kind {
        case .good: "GOOD END"
        case .normal: "NORMAL END"
        case .bad: "BAD END"
        }
    }

    private var message: String {
        let name = heroine?.name ?? ""
        return switch ending.kind {
        case .good: "花火が終わっても、\(name)はつないだ手を離さなかった。"
        case .normal: "\(name)とは、また来週も会う約束をした。\n今はまだ、それで十分だった。"
        case .bad: "\(name)が何を言いかけたのか、\n最後まで聞けないままだった。"
        }
    }
}
