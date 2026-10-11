import FoundationModels

// プロパティの宣言順がそのまま生成順になる。
// セリフを先に生成させることで、ストリーミング中に早く表示を始められる。

@Generable
nonisolated struct GeneratedLine {
    @Guide(description: "ヒロインのセリフ本文のみ。かぎ括弧・名前・ト書きは含めない。口調ルールを厳守し1〜2文")
    var text: String

    @Guide(description: "このセリフを言うときの表情")
    var emotion: Emotion
}

@Generable
nonisolated struct GeneratedChoice {
    @Guide(description: "主人公の返答。25文字以内の自然な話し言葉")
    var text: String

    @Guide(description: "返答の方向性")
    var tone: ChoiceTone

    @Guide(description: "ヒロインの性格から見て、この返答がどれだけ嬉しいか", .range(-3...3))
    var affectionDelta: Int
}

@Generable
nonisolated struct GeneratedTurn {
    @Guide(description: "ヒロインのセリフ。直前の主人公の返答への反応から始める", .count(1...3))
    var lines: [GeneratedLine]

    @Guide(description: "次に主人公が返す選択肢。方向性がそれぞれ異なる3つ", .count(3))
    var choices: [GeneratedChoice]
}

@Generable
nonisolated struct GeneratedSummary {
    @Guide(description: "このシーンで起きた出来事と二人の関係の変化を、第三者視点で80文字以内に要約したもの")
    var summary: String
}
