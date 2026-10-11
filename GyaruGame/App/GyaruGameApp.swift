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
        _game = State(initialValue: GameViewModel(
            content: content,
            repository: SaveRepository(container: container),
            forceMock: CommandLine.arguments.contains("-useMockLLM")
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(game)
                #if DEBUG
                .task {
                    // 開発用: `-startNewGame` でタイトルを飛ばして選択画面へ、
                    // `-startNewGame <heroineID>` ならそのヒロインですぐに始める
                    let args = CommandLine.arguments
                    if let index = args.firstIndex(of: "-startNewGame"), game.screen == .title {
                        if let heroineID = args[safe: index + 1], game.content.heroine(id: heroineID) != nil {
                            game.newGame(heroineID: heroineID)
                        } else {
                            game.showHeroineSelect()
                        }
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
