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

    var body: some View {
        @Bindable var game = game

        ZStack {
            SceneBackgroundView(name: "office_building_night")
                .ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("定時後ローカルLLM")
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("オンデバイスAIで紡ぐ、大人たちの恋の物語")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .shadow(radius: 8)

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        Button(action: game.showHeroineSelect) {
                            Text("はじめから").frame(width: 240)
                        }
                        Button(action: game.continueGame) {
                            Text("つづきから").frame(width: 240)
                        }
                        .disabled(!game.hasContinuableSave)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
                }

                VStack(spacing: 8) {
                    Toggle("モックLLMで遊ぶ（開発用）", isOn: $game.usesMock)
                        .disabled(game.modelUnavailableMessage != nil)
                    if let message = game.modelUnavailableMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }
}

struct EndingView: View {
    @Environment(GameViewModel.self) private var game
    let ending: Ending

    private var heroine: Heroine? {
        game.content.heroine(id: ending.heroineID)
    }

    var body: some View {
        ZStack {
            SceneBackgroundView(name: ending.kind == .good ? "hill_night" : "riverside_evening")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                if let heroine {
                    HeroinePortrait(heroine: heroine, size: 120)
                }
                Text(title)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Button("タイトルへ戻る", action: game.returnToTitle)
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
            }
            .padding(40)
            .frame(maxWidth: 720)
            .glassEffect(.regular, in: .rect(cornerRadius: 32))
            .padding(24)
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
        case .good: "花火の光の中で、\(name)と手をつないだ。\nこれからは、二人で同じ景色を見ていく。"
        case .normal: "\(name)とは、少しだけ特別な友達になれた。\nこの関係の続きは、また来年の夏に。"
        case .bad: "\(name)の気持ちに、最後まで気づけなかった。\n花火の音だけが、やけに大きく響いていた。"
        }
    }
}
