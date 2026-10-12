import MLXFoundationModels
import SwiftUI

/// タイトル画面に出す、ゲームデータ（ローカルLLMの重み）の準備状況。プレイヤーにはモデルではなく追加データとして見せる
struct ModelStatusView: View {
    @Environment(GameViewModel.self) private var game

    /// 状態表示は内容に関係なく常にこの大きさ
    private static let size = CGSize(width: 336, height: 60)

    var body: some View {
        status
            .font(NovelTheme.font(NovelTheme.minimumFontSize))
            .foregroundStyle(NovelTheme.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(width: Self.size.width, height: Self.size.height)
            .novelPanel(cornerRadius: 8)
    }

    @ViewBuilder
    private var status: some View {
        switch game.localModelState {
        case .notDownloaded:
            HStack(spacing: 12) {
                Text("追加データ（\(LocalLLMJudge.approximateDownloadSize)）の\nダウンロードが必要です")
                Button("ダウンロード", action: game.downloadLocalModel)
                    .buttonStyle(NovelButtonStyle(size: CGSize(width: 112, height: 32), fontSize: 13, cornerRadius: 6, isSelected: true))
            }
        case .loading:
            if let download = MLXDownloadProgress.shared.download(forModelID: LocalLLMJudge.modelID) {
                VStack(spacing: 8) {
                    ProgressTrack(fraction: download.fractionCompleted)
                    Text("ダウンロード中 \(Int(download.fractionCompleted * 100))%（\(Self.gigabytes(download.completedBytes)) / \(Self.gigabytes(download.totalBytes))）")
                        .monospacedDigit()
                }
            } else {
                Text("データを読み込んでいます…")
            }
        case .ready:
            Text("準備が完了しました")
        case .failed:
            HStack(spacing: 12) {
                Text("データの準備に失敗しました")
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
