import Foundation

/// ヒロインの人格（instructions）と、毎ターンの状況（prompt）を組み立てる。
/// コンテキストが小さいので、毎ターン新しいセッションを作り、
/// 必要な情報はすべてこのプロンプトに要約して詰める方針。
nonisolated enum PromptBuilder {
    static func instructions(for heroine: Heroine) -> String {
        """
        あなたは社会人の恋愛を描くノベルゲームのシナリオライターです。
        登場人物「\(heroine.name)」のセリフと、主人公の返答の選択肢を書きます。
        主人公は「\(GameConstants.playerName)」（\(GameConstants.playerProfile)）です。登場人物は全員、成人した社会人です。

        # プロフィール
        \(heroine.profile)

        # 口調ルール
        - 一人称は「\(heroine.firstPerson)」、主人公のことは「\(heroine.callsPlayer)」と呼ぶ
        \(heroine.speechRules.map { "- \($0)" }.joined(separator: "\n"))

        # セリフの見本（この口調を真似ること）
        \(heroine.sampleLines.map { "「\($0)」" }.joined(separator: "\n"))

        # 出力ルール
        - lines には\(heroine.name)の発言だけを書く。地の文・ト書き・主人公の発言は書かない
        - choices は主人公の返答の候補。優しい・からかう・素直・そっけない など方向性を変える
        - affectionDelta は\(heroine.name)の性格から見た評価。失礼な返答はマイナスにする
        - 日本語で出力する
        """
    }

    static func turnPrompt(_ request: TurnRequest) -> String {
        let d = request.directive
        var sections: [String] = []

        sections.append("""
        # 場面
        第\(d.chapterNumber)章「\(d.chapterTitle)」／場所: \(d.scene.location)
        状況: \(d.scene.narration)
        このシーンの目標: \(d.scene.goal)
        進行: \(d.phase.instruction)（残り\(d.turnsLeft)ターン）
        """)

        sections.append("""
        # 二人の関係
        好感度 \(request.affection)/100（\(AffectionEngine.relationLabel(for: request.affection))）
        好感度が低いうちは距離を感じさせ、高いほど親しげに話す。
        """)

        if !request.summaries.isEmpty {
            sections.append("# これまでのあらすじ\n" + request.summaries.map { "- \($0)" }.joined(separator: "\n"))
        }

        if !request.lore.isEmpty {
            sections.append("# \(request.heroine.name)に関する設定（自然に会話へ活かす）\n" + request.lore.map { "- \($0.text)" }.joined(separator: "\n"))
        }

        if !request.recentLog.isEmpty {
            sections.append("# 直近の会話\n" + request.recentLog.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"))
        }

        if let lastChoice = request.lastChoice {
            sections.append("# 指示\n主人公の直前の返答「\(lastChoice)」に対する、\(request.heroine.name)の反応のセリフを書いてください。")
        } else {
            sections.append("# 指示\nこの場面で\(request.heroine.name)が最初に話すセリフを書いてください。")
        }

        return sections.joined(separator: "\n\n")
    }

    static let summaryInstructions = "あなたは恋愛アドベンチャーゲームの記録係です。会話ログを読み、後から読み返して思い出せるように簡潔に要約します。"

    static func summaryPrompt(_ request: SummaryRequest) -> String {
        """
        場面: 第\(request.directive.chapterNumber)章「\(request.directive.chapterTitle)」\(request.directive.scene.location)
        登場人物: \(GameConstants.playerName)（主人公、\(GameConstants.playerProfile)）、\(request.heroine.name)

        # 会話ログ
        \(request.log.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"))
        """
    }
}
