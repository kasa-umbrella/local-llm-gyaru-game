import SwiftUI

/// 背景（全画面）＋ヒロイン（中央）＋セリフボックス（下）
struct GameView: View {
    @Environment(GameViewModel.self) private var game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsBacklog = false

    var body: some View {
        ZStack {
            SceneBackgroundView(name: game.directive?.scene.background ?? "")
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: game.directive?.scene.id)

            if let heroine = game.heroine {
                HeroineSpriteView(heroine: heroine, emotion: game.currentEmotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 120)
                    .animation(.easeInOut(duration: 0.25), value: game.currentEmotion)
            }

            VStack(spacing: 20) {
                header
                Spacer()
                if game.showsChoices {
                    ChoiceList(choices: game.choices, onSelect: game.choose)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let notice = game.notice {
                    Text(notice)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .capsule)
                }
                DialogueBox(
                    line: game.currentLine,
                    accentColor: game.heroine.map { Color(hex: $0.themeColor) } ?? .gray,
                    isGenerating: game.isGenerating,
                    canAdvance: game.canAdvance,
                    onAdvance: game.advance
                )
                .frame(maxWidth: 1000)
            }
            .padding(horizontalSizeClass == .compact ? 12 : 24)
            .animation(.easeInOut(duration: 0.2), value: game.showsChoices)

            if game.isTransitioning {
                transitionOverlay
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            game.advance()
            return .handled
        }
        .sheet(isPresented: $showsBacklog) {
            BacklogView(logs: game.backlog)
        }
    }

    /// iPhone の縦画面では章タイトルとボタン類を2段に分ける
    @ViewBuilder
    private var header: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AffectionBadge(affection: game.currentAffection, delta: game.lastAffectionDelta)
                    Spacer()
                    headerButtons
                }
                chapterLabel
            }
        } else {
            HStack(spacing: 12) {
                chapterLabel
                Spacer()
                AffectionBadge(affection: game.currentAffection, delta: game.lastAffectionDelta)
                headerButtons
            }
        }
    }

    @ViewBuilder
    private var chapterLabel: some View {
        if let directive = game.directive {
            Text("第\(directive.chapterNumber)章 \(directive.chapterTitle)　\(directive.scene.location)")
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var headerButtons: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                Button("ログ", systemImage: "text.bubble") { showsBacklog = true }
                Button("タイトル", systemImage: "house") { game.returnToTitle() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private var transitionOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("思い出を整理しています……")
                    .font(.callout)
            }
            .padding(28)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .transition(.opacity)
    }
}

struct BacklogView: View {
    let logs: [DialogueLog]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(logs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.speaker)
                            .font(.caption.bold())
                            .foregroundStyle(log.speaker == GameConstants.playerName ? .blue : .pink)
                        Text(log.text)
                    }
                    .padding(.vertical, 2)
                    .id(log.order)
                }
                .onAppear { proxy.scrollTo(logs.last?.order, anchor: .bottom) }
            }
            .navigationTitle("バックログ")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }
}
