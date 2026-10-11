import Foundation

/// ヒロインの人格（instructions）と、毎ターンの状況（prompt）を組み立てる。
/// コンテキストが小さいので、毎ターン新しいセッションを作り、
/// 必要な情報はすべてこのプロンプトに要約して詰める方針。
nonisolated enum PromptBuilder {
    /// モデルに何を出力させるか
    enum OutputStyle {
        /// セリフの文字列だけ（Apple のオンデバイスモデル用）
        case lineOnly
        /// セリフと表情の構造化出力（ローカルLLM用）。見本のセリフは丸写しされるので渡さない
        case structuredLine
    }

    static func instructions(for heroine: Heroine, style: OutputStyle = .lineOnly) -> String {
        """
        あなたは社会人の恋愛を描くノベルゲームのシナリオライターです。
        登場人物「\(heroine.name)」のセリフと、主人公の返答の選択肢を書きます。
        主人公は「\(GameConstants.playerName)」（\(GameConstants.playerProfile)）です。登場人物は全員、成人した社会人です。

        # プロフィール
        \(heroine.profile)

        # 口調ルール
        - 一人称は「\(heroine.firstPerson)」、主人公のことは「\(heroine.callsPlayer)」と呼ぶ
        \(heroine.speechRules.map { "- \($0)" }.joined(separator: "\n"))

        \(sampleSection(for: heroine, style: style))

        # 出力ルール
        \(outputRules(for: heroine, style: style))
        """
    }

    private static func outputRules(for heroine: Heroine, style: OutputStyle) -> String {
        switch style {
        case .lineOnly:
            """
            - \(heroine.name)のセリフだけを1〜2文で書く
            - かぎ括弧・名前・説明・ト書き・主人公の発言は書かない
            - 見本のセリフをそのまま使わず、この場面に合わせて新しく書く
            """
        case .structuredLine:
            """
            - lines には\(heroine.name)の発言だけを書く。地の文・ト書き・主人公の発言は書かない
            - 一人称と主人公の呼び方を必ず守る
            - この場面と直前のやりとりに合った、新しいセリフを書く
            """
        }
    }

    private static func sampleSection(for heroine: Heroine, style: OutputStyle) -> String {
        switch style {
        case .lineOnly:
            "# セリフの見本（この口調を真似ること）\n" + heroine.sampleLines.map { "「\($0)」" }.joined(separator: "\n") + "\n"
        case .structuredLine:
            ""
        }
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

    // MARK: - 選択肢

    static let choiceInstructions = "あなたは社会人の恋愛を描くノベルゲームのシナリオライターです。主人公「\(GameConstants.playerName)」（\(GameConstants.playerProfile)）の返答を書きます。"

    /// 返答の方向性はシステム側で決めて渡す。モデルには返答の文面だけを書かせる
    static func choicePrompt(heroine: Heroine, directive: SceneDirective, heroineLine: String, tones: [ChoiceTone]) -> String {
        """
        場面: \(directive.scene.location)
        相手: \(heroine.name)（\(heroine.role)）
        相手のセリフ: 「\(heroineLine)」

        主人公の返答を\(tones.count)行で書いてください。
        \(tones.enumerated().map { "\($0.offset + 1)行目: \($0.element.instruction)" }.joined(separator: "\n"))
        各行は返答のセリフだけを25文字以内で。番号・かぎ括弧・説明は付けない。
        """
    }

    /// ローカルLLM用。選択肢を方向性ごとに1つずつ作るプロンプト。
    /// 方向性を番号付きで並べるとモデルが指示語をそのまま写すので、1回に1つの方向性だけを文章で伝える
    static func structuredSingleChoicePrompt(heroine: Heroine, directive: SceneDirective, recentLog: [LogEntry], heroineLine: String, tone: ChoiceTone, avoiding existing: [String]) -> String {
        var sections = ["""
        場面: \(directive.scene.location)
        相手: \(heroine.name)（\(heroine.role)）。\(heroine.tagline)
        """]
        if !recentLog.isEmpty {
            sections.append("直近の会話:\n" + recentLog.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n"))
        }
        var request = """
        \(heroine.name)が主人公にこう言った: 「\(heroineLine)」

        主人公「\(GameConstants.playerName)」として、\(tone.instruction)ような返事を1つ考えてください。
        主人公が実際に口にするセリフだけを、25文字以内で書くこと。相手のセリフを繰り返さないこと。

        お手本（相手のセリフ → 主人公の返事）:
        「今日も残業ですか？」 → 「いや、今日は早く帰れそう」
        """
        if !existing.isEmpty {
            request += "\nすでに考えた返事（これとは違う内容にする）: " + existing.map { "「\($0)」" }.joined(separator: "、")
        }
        sections.append(request)
        return sections.joined(separator: "\n\n")
    }

    // MARK: - 判定（文脈を含めない短い入力にする）

    static func emotionPrompt(line: String) -> String {
        "セリフ: 「\(line)」"
    }

    static func reactionPrompt(heroine: Heroine, heroineLine: String, choice: String) -> String {
        """
        人物の性格: \(heroine.tagline)
        人物の発言: 「\(heroineLine)」
        それに対する相手の返答: 「\(choice)」
        """
    }

    // MARK: - 要約

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
