import Foundation

/// ヒロインの設定集から、今のシーンに関係する知識だけを取り出す簡易 RAG。
/// 規模が小さいうちはタグとキーワードの一致で十分。必要になったら
/// NaturalLanguage の埋め込みによる類似度をスコアに足す。
nonisolated struct LoreRetriever: Sendable {
    let entries: [LoreEntry]

    func retrieve(heroineID: String, sceneTags: [String], recentText: String, limit: Int = 3) -> [LoreEntry] {
        let tags = Set(sceneTags)
        let scored: [(entry: LoreEntry, score: Int)] = entries
            .filter { $0.heroineID == heroineID }
            .map { ($0, score($0, tags: tags, recentText: recentText)) }
            .filter { $0.score > 0 }
        let ranked = scored.sorted { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.entry.id < rhs.entry.id
        }
        return ranked.prefix(limit).map(\.entry)
    }

    /// タグ一致は2点、直近の会話に含まれるキーワードは1点
    private func score(_ entry: LoreEntry, tags: Set<String>, recentText: String) -> Int {
        let tagScore = entry.tags.filter { tags.contains($0) }.count * 2
        let keywordScore = entry.keywords.filter { recentText.contains($0) }.count
        return tagScore + keywordScore
    }
}
