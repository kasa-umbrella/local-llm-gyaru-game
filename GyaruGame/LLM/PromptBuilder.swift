import Foundation

/// 判定役の LLM に渡す instructions と prompt を組み立てる。
/// LLM はセリフを書かず、選んだ選択肢でひよりの気持ちがどう動いたかを数字で答えるだけ
nonisolated enum PromptBuilder {
    static func judgeInstructions(for heroine: Heroine) -> String {
        let axes = Axis.allCases.map { "- \($0.label): \($0.meaning)" }.joined(separator: "\n")
        return """
        あなたは恋愛ノベルゲームの判定係です。主人公「\(GameConstants.playerName)」（\(GameConstants.playerProfile)）の発言と、それを受けた「\(heroine.name)」の反応を読み、\(heroine.name)の気持ちがどう動いたかを判定します。

        # \(heroine.name)
        \(heroine.profile)

        # 気持ちの3つの軸
        \(axes)

        # 判定のしかた
        - 発言の内容だけでなく、\(heroine.name)の反応の様子と、その日の気分をふまえて判定する
        - 同じような発言でも、場面や気分によって動く軸は変わる
        - 各軸は -2〜+3 の整数。動かなければ 0、嫌な気持ちになったらマイナス
        - 次の形の1行だけを書く。説明は書かない
        ときめき +1 / 信頼 0 / ノリ +2
        """
    }

    static func judgePrompt(_ request: JudgeRequest) -> String {
        let flow = request.recentLines.map { line in
            line.speaker.map { "\($0): \(line.text)" } ?? "（\(line.text)）"
        }
        var sections = ["""
        場面: \(request.scene.month)月、\(request.scene.location)
        \(request.heroine.name)のその日の気分: \(request.mood.label)
        """]
        if !flow.isEmpty {
            sections.append("# ここまでの流れ\n" + flow.joined(separator: "\n"))
        }
        sections.append("""
        # 判定する場面
        \(GameConstants.playerName): \(request.playerLine)
        \(request.heroine.name): \(request.reaction)
        """)
        return sections.joined(separator: "\n\n")
    }
}
