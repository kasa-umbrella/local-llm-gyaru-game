import SwiftUI

/// 背景（全画面）＋ヒロイン（中央）＋テキストウィンドウ（下）
struct GameView: View {
    @Environment(GameViewModel.self) private var game
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var typewriter = Typewriter()
    @State private var showsBacklog = false
    @State private var isAutoOn = false
    @State private var isSkipOn = false

    private static let playerNameColor = Color(white: 0.55)

    private var metrics: NovelTheme.Metrics {
        NovelTheme.Metrics(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    /// 表示中の行を一意に表すキー。変わったら文字送りを最初からやり直す
    private var lineKey: Int {
        var hasher = Hasher()
        hasher.combine(game.scene?.id)
        hasher.combine(game.cursor)
        return hasher.finalize()
    }

    var body: some View {
        ZStack {
            SceneBackgroundView(name: game.scene?.background ?? "")
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: game.scene?.id)

            // 立ち絵は画面下端まで伸ばし、下半身は半透明のテキストウィンドウ越しに見せる。
            // 登場は左からスライドイン、退場はフェードアウト
            ZStack {
                if game.isHeroineOnStage {
                    HeroineSpriteView(heroine: game.heroine, emotion: game.currentEmotion)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, metrics.isShort ? 24 : 60)
                        .ignoresSafeArea(edges: .bottom)
                        .animation(.easeInOut(duration: 0.25), value: game.currentEmotion)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.easeOut(duration: 0.45), value: game.isHeroineOnStage)

            VStack(spacing: 0) {
                header
                Spacer(minLength: metrics.isShort ? 4 : 12)
                if game.showsChoices {
                    ChoiceList(metrics: metrics, choices: game.choices) { choice in
                        game.choose(choice)
                    }
                    .transition(.opacity)
                }
                Spacer(minLength: metrics.isShort ? 4 : 12)
                dialogueWindow
                    .padding(.top, metrics.namePlateSize.height * 0.5)
            }
            .padding(metrics.screenPadding)
            .animation(.easeOut(duration: 0.18), value: game.showsChoices)

            if game.isTransitioning {
                loadingOverlay
            }

            if showsBacklog {
                BacklogOverlay(metrics: metrics, logs: game.backlog) { showsBacklog = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsBacklog)
        #if DEBUG
        .onAppear {
            // 開発用: `-autoMode` で起動するとオートをオンにして始める
            if CommandLine.arguments.contains("-autoMode") { isAutoOn = true }
        }
        #endif
        .onChange(of: lineKey, initial: true) { updateTypewriter() }
        .onChange(of: game.currentLine?.text) { updateTypewriter() }
        .onChange(of: game.showsChoices) { _, shows in
            if shows { isSkipOn = false }
        }
        .task(id: AutoAdvanceKey(lineKey: lineKey, isTyping: typewriter.isTyping, canAdvance: game.canAdvance, isAutoOn: isAutoOn, isSkipOn: isSkipOn)) {
            await autoAdvanceIfNeeded()
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            handleAdvance()
            return .handled
        }
    }

    // MARK: - パーツ

    /// 横幅が足りなければ、開発用のパラメータ表示を章プレートの下の段に回す（それでも入らなければ2列×2段）
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                chapterPlate
                Spacer()
                debugStats(columns: 4)
            }
            VStack(alignment: .leading, spacing: metrics.debugStatSpacing) {
                chapterPlate
                debugStats(columns: 4)
            }
            VStack(alignment: .leading, spacing: metrics.debugStatSpacing) {
                chapterPlate
                debugStats(columns: 2)
            }
        }
    }

    @ViewBuilder
    private func debugStats(columns: Int) -> some View {
        #if DEBUG
        DebugStatsRow(metrics: metrics, columns: columns, feelings: game.progress.feelings, delta: game.lastJudgment, mood: game.mood)
        #endif
    }

    @ViewBuilder
    private var chapterPlate: some View {
        if let scene = game.scene {
            Text("\(scene.month)月　\(scene.location)")
                .font(NovelTheme.font(metrics.chapterFontSize))
                .foregroundStyle(NovelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(NovelTheme.minimumScale(for: metrics.chapterFontSize))
                .padding(.horizontal, 14)
                .frame(width: metrics.chapterPlateSize.width, height: metrics.chapterPlateSize.height, alignment: .leading)
                .novelPanel(cornerRadius: 6)
        }
    }

    private var dialogueWindow: some View {
        let line = game.currentLine
        let speaker = line?.speaker
        return DialogueWindow(
            metrics: metrics,
            speaker: speaker,
            speakerColor: speaker == game.heroine.name ? Color(hex: game.heroine.themeColor) : Self.playerNameColor,
            text: typewriter.attributedText(color: NovelTheme.text),
            isNarration: line != nil && speaker == nil,
            indicator: indicator,
            isAutoOn: isAutoOn,
            isSkipOn: isSkipOn,
            onAdvance: {
                isSkipOn = false
                handleAdvance()
            },
            onLog: { showsBacklog = true },
            onAuto: {
                isAutoOn.toggle()
                isSkipOn = false
            },
            onSkip: {
                isSkipOn.toggle()
                isAutoOn = false
                if isSkipOn { typewriter.complete() }
            },
            onTitle: game.returnToTitle
        )
    }

    private var indicator: DialogueWindow.Indicator {
        !typewriter.isTyping && game.canAdvance ? .next : .none
    }

    private var loadingOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.3).ignoresSafeArea()
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("NOW LOADING")
                    .font(NovelTheme.font(14))
                    .foregroundStyle(.white)
                    .novelTextOutline()
            }
            .padding(metrics.screenPadding + 8)
        }
        .transition(.opacity)
    }

    // MARK: - 進行

    private func updateTypewriter() {
        typewriter.show(game.currentLine?.text ?? "", key: lineKey, instant: isSkipOn)
    }

    /// 文字送り中なら全文を表示し、表示し終わっていれば次の行へ
    private func handleAdvance() {
        guard !showsBacklog else { return }
        if typewriter.isTyping {
            typewriter.complete()
        } else {
            game.advance()
        }
    }

    private func autoAdvanceIfNeeded() async {
        guard isAutoOn || isSkipOn, !typewriter.isTyping, game.canAdvance, !showsBacklog else { return }
        let wait: Duration = isSkipOn
            ? .milliseconds(80)
            : .seconds(1.0) + .milliseconds(40 * typewriter.text.count)
        try? await Task.sleep(for: wait)
        guard !Task.isCancelled else { return }
        game.advance()
    }

    private struct AutoAdvanceKey: Hashable {
        let lineKey: Int
        let isTyping: Bool
        let canAdvance: Bool
        let isAutoOn: Bool
        let isSkipOn: Bool
    }
}

/// 全画面のバックログ。名前の列は常に同じ幅
struct BacklogOverlay: View {
    let metrics: NovelTheme.Metrics
    let logs: [DialogueLog]
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 16) {
                HStack {
                    Text("バックログ")
                        .font(NovelTheme.font(metrics.isCompact ? 18 : 22, bold: true))
                        .foregroundStyle(NovelTheme.text)
                    Spacer()
                    Button("閉じる", action: onClose)
                        .buttonStyle(NovelButtonStyle(size: CGSize(width: 110, height: 38), fontSize: 15))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(logs) { log in
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(log.speaker)
                                        .font(NovelTheme.font(metrics.isCompact ? 13 : 15, bold: true))
                                        .foregroundStyle(log.speaker == GameConstants.playerName ? Color(white: 0.78) : NovelTheme.accent)
                                        .lineLimit(1)
                                        .minimumScaleFactor(NovelTheme.minimumScale(for: metrics.isCompact ? 13 : 15))
                                        .frame(width: metrics.isCompact ? 84 : 110, alignment: .trailing)
                                    Text(log.text)
                                        .font(NovelTheme.font(metrics.isCompact ? 15 : 17))
                                        .foregroundStyle(NovelTheme.text)
                                        .lineSpacing(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(log.order)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onAppear { proxy.scrollTo(logs.last?.order, anchor: .bottom) }
                }
            }
            .padding(metrics.screenPadding + 8)
            .frame(maxWidth: 960)
        }
    }
}
