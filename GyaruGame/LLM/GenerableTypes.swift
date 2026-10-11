import FoundationModels

// MARK: - Apple のオンデバイスモデル用
// 構造化出力（@Generable）はガードレールが厳しく、キャラ設定や場面を含む入力だと弾かれやすい。
// そのため、セリフと選択肢は文字列で生成し、構造化出力は文脈を含まない短い判定にだけ使う。

/// セリフ1行から表情を判定する
@Generable
nonisolated struct EmotionTag {
    @Guide(description: "このセリフを言うときの表情。normal=落ち着いている, smile=嬉しい・楽しい, shy=照れている, angry=怒っている・拗ねている, sad=悲しい・寂しい, surprised=驚いている")
    var emotion: Emotion
}

/// 主人公の返答を受けた人物の嬉しさを判定する
@Generable
nonisolated struct ReactionScore {
    @Guide(description: "人物の性格から見て、この返答がどれだけ嬉しいか。失礼な返答はマイナス", .range(-3...3))
    var delta: Int
}

// MARK: - ローカルLLM用（ガードレールがないので、セリフも選択肢も構造化出力で出す）
// プロパティの宣言順がそのまま生成順になる。

@Generable
nonisolated struct GeneratedLine {
    @Guide(description: "ヒロインのセリフ本文のみ。かぎ括弧・名前・ト書きは含めない。1〜2文")
    var text: String

    @Guide(description: "このセリフを言うときの表情")
    var emotion: Emotion
}

/// 1回目: ヒロインのセリフ
@Generable
nonisolated struct GeneratedReply {
    @Guide(description: "ヒロインのセリフ。直前の主人公の返答への反応から始める", .count(1...2))
    var lines: [GeneratedLine]
}

@Generable
nonisolated struct GeneratedChoice {
    @Guide(description: "主人公の返答。主人公の口調で、25文字以内の自然な話し言葉")
    var text: String

    @Guide(description: "相手の性格から見て、この返答がどれだけ嬉しいか。失礼な返答はマイナス", .range(-3...3))
    var affectionDelta: Int
}
