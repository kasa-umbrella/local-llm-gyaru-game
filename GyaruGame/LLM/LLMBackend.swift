import Foundation

/// セリフを生成するエンジン
enum LLMBackend: String, CaseIterable, Identifiable {
    /// MLX で動かすローカルLLM（Qwen3.5）
    case local
    /// Apple のオンデバイスモデル（Foundation Models）
    case apple
    /// 開発用の固定セリフ
    case mock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: "ローカルLLM"
        case .apple: "Apple"
        case .mock: "モック"
        }
    }

    private static let storageKey = "llmBackend"

    /// 前回選んだエンジン。初回は Mac ならローカルLLM、iPhone なら Apple のモデル
    static var saved: LLMBackend {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let backend = LLMBackend(rawValue: raw) {
            return backend
        }
        #if os(macOS)
        return .local
        #else
        return .apple
        #endif
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}

/// ローカルLLMのモデルの準備状況
enum LocalModelState: Equatable {
    /// まだダウンロードしていない
    case notDownloaded
    /// ダウンロード中、またはメモリに読み込み中
    case loading
    case ready
    case failed(String)
}
