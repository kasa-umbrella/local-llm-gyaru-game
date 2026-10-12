import Foundation

/// ひよりの気持ちの3つの軸。それぞれが最終盤のルートに対応する
nonisolated enum Axis: String, Codable, CaseIterable, Sendable {
    case tokimeki, trust, nori

    var label: String {
        switch self {
        case .tokimeki: "ときめき"
        case .trust: "信頼"
        case .nori: "ノリ"
        }
    }

    /// 判定役の LLM に渡す、この軸が上がるときの気持ち
    var meaning: String {
        switch self {
        case .tokimeki: "主人公を異性として意識した、ドキッとした"
        case .trust: "主人公を頼れる、本音を話せる相手だと感じた"
        case .nori: "主人公といると楽しい、ノリが合うと感じた"
        }
    }
}

/// 3つの軸の値。プレイヤーには見せない
nonisolated struct Feelings: Codable, Equatable, Sendable {
    /// 1回の選択で動く幅（判定役の LLM の出力をこの範囲に収める）
    static let deltaRange = -2...3
    static let valueRange = 0...100

    var tokimeki = 0
    var trust = 0
    var nori = 0

    subscript(axis: Axis) -> Int {
        get {
            switch axis {
            case .tokimeki: tokimeki
            case .trust: trust
            case .nori: nori
            }
        }
        set {
            switch axis {
            case .tokimeki: tokimeki = newValue
            case .trust: trust = newValue
            case .nori: nori = newValue
            }
        }
    }

    /// 判定の変化量を足す。各軸は valueRange に収める
    func adding(_ delta: Feelings) -> Feelings {
        var result = self
        for axis in Axis.allCases {
            result[axis] = (self[axis] + delta[axis]).clamped(to: Self.valueRange)
        }
        return result
    }

    /// いちばん高い軸（同点なら Axis.allCases の順で先のもの）
    var strongest: Axis {
        Axis.allCases.max { self[$0] < self[$1] } ?? .tokimeki
    }
}

/// シーンごとにランダムで決まる、ひよりのその日の気分。判定にだけ効かせる
nonisolated enum Mood: String, CaseIterable, Sendable {
    case cheerful, tired, sulky, giddy, calm

    var label: String {
        switch self {
        case .cheerful: "上機嫌"
        case .tired: "疲れ気味"
        case .sulky: "拗ね気味"
        case .giddy: "浮かれ気味"
        case .calm: "普段どおり"
        }
    }
}

/// 種を指定できる乱数（SplitMix64）。テストでは種を固定して、山札と分岐のくじを再現する
nonisolated struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64 = .random(in: 0...UInt64.max)) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
