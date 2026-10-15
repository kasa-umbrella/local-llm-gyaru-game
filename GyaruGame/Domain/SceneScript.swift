import Foundation

/// 画面に出す1行。speaker が nil なら地の文
nonisolated struct DialogueLine: Equatable, Sendable {
    var speaker: String?
    var text: String
    var emotion: Emotion = .normal
    /// この行を表示している間、ヒロインが画面に出ているか
    var showsHeroine = false
}

/// 画面に出す選択肢
nonisolated struct ChoiceOption: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
}

/// 人が書いたシーンのシナリオ。セリフ・選択肢・反応はすべてここで決め、LLM は選んだ結果の判定だけを担当する
/// （自由入力では、反応の種類を選ぶところまで。セリフは `free_replies.json` の人が書いたもの）。
/// バンドル内の `script_<シーンID>.json` から読み込む。
nonisolated struct SceneScript: Codable, Sendable {
    let sceneID: String
    let beats: [ScriptBeat]
}

/// シーンの1区切り
nonisolated enum ScriptBeat: Codable, Sendable {
    /// 地の文（そのまま出す）
    case narration(String)
    /// ヒロインのセリフ
    case line(ScriptLine)
    /// ヒロイン以外のセリフ（主人公や脇役）。そのまま出す
    case speech(ScriptSpeech)
    /// 主人公の選択肢の候補。4つ以上書いておくと、毎回そこから3つをランダムに出す。
    /// `allowsFreeInput` なら、選択肢のほかに「自分の言葉で伝える」入力欄も出す
    case choice([ScriptChoice], allowsFreeInput: Bool)
    /// ヒロインが画面に出てくる。シーンの頭では画面にいないので、出したいところに書く
    case enter
    /// ヒロインが画面からいなくなる
    case exit
    /// 背景を切り替える（アセット `bg_<name>` の name）。時間が進んだり場所を移ったりするところに書く。
    /// シーンの頭の背景は story.json の `background`
    case background(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, emotion, options, speaker, freeInput, name
    }

    private enum BeatType: String, Codable {
        case narration, line, speech, choice, enter, exit, background
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BeatType.self, forKey: .type) {
        case .narration:
            self = .narration(try container.decode(String.self, forKey: .text))
        case .line:
            self = .line(ScriptLine(
                text: try container.decode(String.self, forKey: .text),
                emotion: try container.decodeIfPresent(Emotion.self, forKey: .emotion) ?? .normal
            ))
        case .speech:
            self = .speech(ScriptSpeech(
                speaker: try container.decode(String.self, forKey: .speaker),
                text: try container.decode(String.self, forKey: .text)
            ))
        case .choice:
            self = .choice(
                try container.decode([ScriptChoice].self, forKey: .options),
                allowsFreeInput: try container.decodeIfPresent(Bool.self, forKey: .freeInput) ?? false
            )
        case .enter:
            self = .enter
        case .exit:
            self = .exit
        case .background:
            self = .background(try container.decode(String.self, forKey: .name))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .narration(let text):
            try container.encode(BeatType.narration, forKey: .type)
            try container.encode(text, forKey: .text)
        case .line(let line):
            try container.encode(BeatType.line, forKey: .type)
            try container.encode(line.text, forKey: .text)
            try container.encode(line.emotion, forKey: .emotion)
        case .speech(let speech):
            try container.encode(BeatType.speech, forKey: .type)
            try container.encode(speech.speaker, forKey: .speaker)
            try container.encode(speech.text, forKey: .text)
        case .choice(let options, let allowsFreeInput):
            try container.encode(BeatType.choice, forKey: .type)
            if allowsFreeInput { try container.encode(true, forKey: .freeInput) }
            try container.encode(options, forKey: .options)
        case .enter:
            try container.encode(BeatType.enter, forKey: .type)
        case .exit:
            try container.encode(BeatType.exit, forKey: .type)
        case .background(let name):
            try container.encode(BeatType.background, forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

nonisolated struct ScriptLine: Codable, Sendable {
    let text: String
    let emotion: Emotion
}

nonisolated struct ScriptSpeech: Codable, Sendable {
    /// シナリオ上で主人公を表す話者名。表示時に主人公の名前に置き換える
    static let playerSpeaker = "player"

    let speaker: String
    let text: String

    var displayName: String {
        speaker == Self.playerSpeaker ? GameConstants.playerName : speaker
    }
}

nonisolated struct ScriptChoice: Codable, Sendable {
    /// 一度に出す選択肢の数
    static let shownCount = 3

    let text: String
    let reaction: ScriptReaction
}

/// 選択肢に対するヒロインの反応（人が書いたものをそのまま出す）
nonisolated struct ScriptReaction: Codable, Sendable {
    let text: String
    let emotion: Emotion
}
