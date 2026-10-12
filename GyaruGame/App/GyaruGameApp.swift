import SwiftData
import SwiftUI

@main
struct GyaruGameApp: App {
    private let container: ModelContainer
    @State private var game: GameViewModel

    init() {
        let container: ModelContainer
        let content: GameContent
        do {
            container = try SaveRepository.makeContainer()
            content = try GameContent.loadFromBundle()
        } catch {
            fatalError("ゲームデータの初期化に失敗しました: \(error)")
        }
        self.container = container
        _game = State(initialValue: GameViewModel(content: content, repository: SaveRepository(container: container)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(game)
                #if DEBUG
                .task {
                    // 開発用: `-startNewGame` でタイトルを飛ばして新しく始める（モデルの準備ができてから）
                    if CommandLine.arguments.contains("-startNewGame"), game.screen == .title {
                        while !game.isModelReady, !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                        if game.isModelReady { game.newGame() }
                    }
                }
                #endif
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 640)
                #else
                .persistentSystemOverlays(.hidden)
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
