import Foundation

/// 自由入力への、ひよりの反応の種類。
/// LLM は主人公の一言を読んでこの中から1つを選ぶだけで、セリフは `free_replies.json` に人が書いたものをそのまま出す
nonisolated enum ReplyKind: String, Codable, CaseIterable, Sendable {
    case laugh, flutter, relief, tease, puzzled, upset, plain

    /// 判定役の LLM が答える名前。軸の名前（ときめき・信頼・ノリ）とは重ならないようにする
    var label: String {
        switch self {
        case .laugh: "爆笑"
        case .flutter: "照れ"
        case .relief: "安心"
        case .tease: "ツッコミ"
        case .puzzled: "困惑"
        case .upset: "ムッとする"
        case .plain: "ふつう"
        }
    }

    /// 判定役の LLM に渡す、この反応を選ぶ場面。
    /// 小さいモデルは「安心」や「ムッとする」に偏りやすいので、選んではいけない場合も書いておく
    var meaning: String {
        switch self {
        case .laugh: "ふざけた一言や気の利いた返しで、ひよりが吹き出した・ノってきた"
        case .flutter: "ひよりを褒めた、好意をにおわせた、ドキッとさせた"
        case .relief: "悩みや本音を打ち明けた、ひよりを気遣った、頼った。短い相づちでは選ばない"
        case .tease: "自慢や調子に乗った発言、へんな発言に、ひよりが呆れながらツッコんだ"
        case .puzzled: "唐突で意味がわからない、場面と関係がない"
        case .upset: "悪意がある、冷たい、ひよりを見下した・傷つけた。へんなことを言っただけでは選ばない"
        case .plain: "相づち、了解、質問、雑談など、気持ちが動かない一言。迷ったらこれ"
        }
    }

    /// この反応のとき、1回で上げられる気持ちの上限。
    /// 判定が反応と食い違っても（ムッとしたのにときめきが上がるなど）、気持ちは反応より先に進まない
    var deltaCeiling: Int {
        switch self {
        case .upset: 0
        case .puzzled, .plain: 1
        case .laugh, .flutter, .relief, .tease: Feelings.deltaRange.upperBound
        }
    }
}

/// 自由入力の判定結果
nonisolated struct FreeInputJudgment: Equatable, Sendable {
    let kind: ReplyKind
    let delta: Feelings

    /// 判定が読み取れなかったとき。当たり障りのない相づちで、気持ちは動かさない
    static let fallback = FreeInputJudgment(kind: .plain, delta: Feelings())
}

/// 自由入力への反応のセリフ集（人が書く）。反応の種類ごとに複数書いておき、毎回ちがうものを出す
nonisolated struct FreeReplies: Codable, Sendable {
    /// セリフ集がまるごと欠けていても止まらないための最後の手段
    static let lastResort = ScriptReaction(text: "……そうっすか", emotion: .normal)

    /// 反応の種類（`ReplyKind.rawValue`）→ 反応の候補
    let replies: [String: [ScriptReaction]]

    func candidates(for kind: ReplyKind) -> [ScriptReaction] {
        replies[kind.rawValue] ?? []
    }

    /// 種類に合う反応を1つ選ぶ。まだ出していないものを優先し、使い切っていたらその種類の全部から選ぶ
    func pick(for kind: ReplyKind, avoiding used: Set<String>, using generator: inout some RandomNumberGenerator) -> ScriptReaction {
        let all = candidates(for: kind)
        let unused = all.filter { !used.contains($0.text) }
        return (unused.isEmpty ? all : unused).randomElement(using: &generator) ?? Self.lastResort
    }
}

/// プレイヤーが入力した一言の扱い
nonisolated enum FreeInput {
    /// 入力できる文字数
    static let characterLimit = 40

    /// 判定役の答えを待つ上限。これを過ぎたら、当たり障りのない相づちで先へ進む
    /// （入力した一言の反応は、判定が出るまで先へ進めないので、止まったままにしない）
    static let judgmentTimeout: Duration = .seconds(20)

    /// 改行は空白にし、前後の空白を削って、文字数の上限で切る。何も残らなければ nil
    static func sanitized(_ raw: String) -> String? {
        let oneLine = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(characterLimit)).trimmingCharacters(in: .whitespaces)
    }
}
