import Foundation
@testable import GyaruGame

/// LLM なしで進行ロジックを確認するためのテスト用スタブ。決まった判定を返す
final class StubJudge: FeelingJudging {
    private let respond: (JudgeRequest) -> String
    private(set) var requests: [JudgeRequest] = []

    init(_ respond: @escaping (JudgeRequest) -> String = { _ in "ときめき +1 / 信頼 0 / ノリ +2" }) {
        self.respond = respond
    }

    func prewarm() {}

    func judge(_ request: JudgeRequest) async throws -> String {
        requests.append(request)
        return respond(request)
    }
}
