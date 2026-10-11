import MLXFoundationModels
import SwiftUI

/// タイトル画面の生成エンジン切り替えと、その準備状況の表示
struct EngineSelector: View {
    @Environment(GameViewModel.self) private var game

    private static let buttonSize = CGSize(width: 108, height: 34)
    private static let spacing: CGFloat = 6
    /// 状態表示は内容に関係なく常にこの大きさ
    private static let statusSize = CGSize(width: buttonSize.width * 3 + spacing * 2, height: 60)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: Self.spacing) {
                ForEach(LLMBackend.allCases) { backend in
                    Button(backend.label) { game.backend = backend }
                        .buttonStyle(NovelButtonStyle(size: Self.buttonSize, fontSize: 14, cornerRadius: 8, isSelected: game.backend == backend))
                }
            }
            status
                .font(NovelTheme.font(NovelTheme.minimumFontSize))
                .foregroundStyle(NovelTheme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(width: Self.statusSize.width, height: Self.statusSize.height)
                .novelPanel(cornerRadius: 8)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch game.backend {
        case .local:
            localStatus
        case .apple:
            Text(game.appleModelUnavailableMessage ?? "Apple Intelligence のオンデバイスモデルを使います")
                .foregroundStyle(game.appleModelUnavailableMessage == nil ? NovelTheme.text : NovelTheme.accent)
        case .mock:
            Text("固定のセリフで画面の動きを確かめる開発用モードです")
        }
    }

    @ViewBuilder
    private var localStatus: some View {
        let name = LocalLLMDialogueGenerator.modelDisplayName
        switch game.localModelState {
        case .notDownloaded:
            HStack(spacing: 12) {
                Text("\(name)（\(LocalLLMDialogueGenerator.approximateDownloadSize)）\nダウンロードが必要です")
                Button("ダウンロード", action: game.downloadLocalModel)
                    .buttonStyle(NovelButtonStyle(size: CGSize(width: 112, height: 32), fontSize: 13, cornerRadius: 6, isSelected: true))
            }
        case .loading:
            if let download = MLXDownloadProgress.shared.download(forModelID: LocalLLMDialogueGenerator.modelID) {
                VStack(spacing: 8) {
                    ProgressTrack(fraction: download.fractionCompleted)
                    Text("ダウンロード中 \(Int(download.fractionCompleted * 100))%（\(Self.gigabytes(download.completedBytes)) / \(Self.gigabytes(download.totalBytes))）")
                        .monospacedDigit()
                }
            } else {
                Text("\(name) を読み込んでいます…")
            }
        case .ready:
            Text("\(name) の準備ができました")
        case .failed:
            HStack(spacing: 12) {
                Text("準備に失敗しました")
                    .foregroundStyle(NovelTheme.accent)
                Button("再試行", action: game.downloadLocalModel)
                    .buttonStyle(NovelButtonStyle(size: CGSize(width: 88, height: 32), fontSize: 13, cornerRadius: 6))
            }
        }
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1fGB", Double(bytes) / 1_000_000_000)
    }
}

/// 細い進捗バー（固定幅）
private struct ProgressTrack: View {
    let fraction: Double
    private static let width: CGFloat = 260

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.2))
            Capsule().fill(NovelTheme.accent)
                .frame(width: Self.width * min(max(fraction, 0), 1))
        }
        .frame(width: Self.width, height: 4)
    }
}
