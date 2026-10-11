import Foundation

/// 文字列で生成したセリフや選択肢から、モデルが付けがちな余計な文字を取り除く
nonisolated enum GeneratedTextCleaner {
    /// セリフ本文の最大文数（テキストウィンドウに収まる量）
    static let maxSentences = 2

    /// ヒロインのセリフ。ト書きや見出しを切り落とし、かぎ括弧を外して2文までにする
    static func line(_ raw: String) -> String {
        var text = raw
        // 「【選択肢】」などの見出しや、「――澪は〜」のようなト書きから後ろは捨てる
        for marker in ["【", "――", "（", "("] {
            if let range = text.range(of: marker), range.lowerBound != text.startIndex {
                text = String(text[..<range.lowerBound])
            }
        }
        // 2行目以降は別のセリフやト書きが続くことが多いので、最初の1行だけを使う
        text = text
            .components(separatedBy: .newlines)
            .map(stripPrefix)
            .first { !$0.isEmpty } ?? ""
        text = removeQuotes(text)
        return limitSentences(text, to: maxSentences)
    }

    /// 選択肢。番号や名前の前置き、かぎ括弧を外して空行を除く
    static func choices(_ raw: String, count: Int) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { choice($0) }
            .filter { !$0.isEmpty }
            .prefix(count)
            .map { $0 }
    }

    /// 思考型モデルが出す <think>…</think> を取り除く。「→」より前（お手本の形式を真似た相手のセリフ）も捨てる
    static func removingReasoning(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        if let arrow = text.range(of: "→", options: .backwards) {
            text = String(text[arrow.upperBound...])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 選択肢1つ分。番号や名前の前置き、かぎ括弧を外す
    static func choice(_ raw: String) -> String {
        removeQuotes(stripPrefix(raw))
    }

    /// 選択肢として使えるか。ヒロインのセリフの写し、指示語の写し、壊れた出力をはじく
    static func isUsableChoice(_ text: String, heroineLine: String, others: [String]) -> Bool {
        rejectionReason(for: text, heroineLine: heroineLine, others: others) == nil
    }

    /// 選択肢として使えない理由（使えるなら nil）
    static func rejectionReason(for text: String, heroineLine: String, others: [String]) -> String? {
        let key = comparisonKey(text)
        guard (2...40).contains(text.count), key.count >= 2 else { return "長さ" }
        // 「3000000…」のような壊れた出力
        let letterRatio = Double(key.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count) / Double(key.unicodeScalars.count)
        guard letterRatio >= 0.7 else { return "文字以外が多い" }
        // 渡した方向性の指示語をそのまま書いたもの
        guard !ChoiceTone.allCases.contains(where: { key.contains(comparisonKey($0.instruction)) }) else { return "指示語の写し" }
        // ヒロインのセリフの写し
        guard similarity(of: key, and: comparisonKey(heroineLine)) < 0.6 else { return "セリフの写し" }
        guard !others.contains(where: { similarity(of: comparisonKey($0), and: key) >= duplicateSimilarity }) else { return "重複" }
        return nil
    }

    /// これ以上似ていたら同じ選択肢とみなす（2文字ずつの組の Dice 係数）
    static let duplicateSimilarity = 0.75

    /// 同じ内容（ほぼ同じを含む）の選択肢のうち、2つ目以降のインデックスを返す
    static func duplicateIndices(in choices: [String]) -> [Int] {
        let keys = choices.map(comparisonKey)
        return keys.indices.filter { index in
            keys[..<index].contains { similarity(of: $0, and: keys[index]) >= duplicateSimilarity }
        }
    }

    /// 2文字ずつの組（バイグラム）がどれだけ共通しているか（0〜1）
    static func similarity(of lhs: String, and rhs: String) -> Double {
        if lhs == rhs { return 1 }
        let lhsPairs = bigrams(lhs), rhsPairs = bigrams(rhs)
        guard !lhsPairs.isEmpty, !rhsPairs.isEmpty else { return 0 }
        return 2 * Double(lhsPairs.intersection(rhsPairs).count) / Double(lhsPairs.count + rhsPairs.count)
    }

    private static func bigrams(_ text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count > 1 else { return Set([text]) }
        return Set((0..<characters.count - 1).map { String(characters[$0...$0 + 1]) })
    }

    /// 句読点・記号・空白を除いた比較用の文字列
    private static func comparisonKey(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).contains($0) })
    }

    /// 行頭の「1.」「・」「ユウキ：」「**」などを外す
    private static func stripPrefix(_ line: String) -> String {
        var text = line.replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespaces)
        for pattern in [#"^[0-9０-９]+[.．)）、:：]\s*"#, #"^[-・*]\s*"#, #"^[^「」:：]{1,10}[:：]\s*"#] {
            if let range = text.range(of: pattern, options: .regularExpression) {
                text.removeSubrange(range)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func removeQuotes(_ text: String) -> String {
        text.replacingOccurrences(of: #"[「」『』"]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 「。」「！」「？」で区切って先頭から指定の文数だけ残す。「？！」のような連続は1つと数える
    private static func limitSentences(_ text: String, to limit: Int) -> String {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?"]
        let characters = Array(text)
        var count = 0
        for (index, character) in characters.enumerated() where terminators.contains(character) {
            let next = characters[safe: index + 1]
            if let next, terminators.contains(next) { continue }
            count += 1
            if count == limit {
                return String(characters[...index]).trimmingCharacters(in: .whitespaces)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
