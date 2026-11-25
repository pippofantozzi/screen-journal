import Foundation
import JournalCore

/// A hosted decision model behind the Vercel AI Gateway's System One endpoint.
/// The key is `GatewayKey.current()`; it is never stored in the journal.
struct DecisionGateway: Sendable {
    static let url = URL(string: "https://ai-gateway.vercel.sh/typesafe/v1/systemone")!
    /// Reads text and screenshots, about a second a session. On the graded eval set (`scripts/decision-eval.py`) it got
    /// 84% of sessions right on all three answers with the screenshot and 74% from text alone; `baseten/bison-1` (31B, three times the price) got 82% and 78%.
    static let model = "baseten/groundhog-1"
    /// Every request goes only to providers that keep nothing, and none that train on prompts.
    /// Needs the key's Vercel team on Pro: on Hobby the gateway refuses every request with 403.
    static let zeroRetention = true

    private let key: String

    static func configured() -> DecisionGateway? {
        GatewayKey.current().map(DecisionGateway.init)
    }

    init(key: String) {
        self.key = key
    }

    /// One throwaway question, so Settings can say whether the key works.
    func check() async -> Result<Void, LabelError> {
        await answers(.probe, kinds: LabelSetup().kinds).map { _ in () }
    }

    func answers(_ state: SessionState, kinds: [TaskKind], screenshot: Data? = nil) async -> Result<SystemOne.Answers, LabelError> {
        let body: Data
        do { body = try Self.body(state, kinds: kinds, screenshot: screenshot) } catch { return .failure(LabelError(message: error.localizedDescription)) }
        return await reply(to: body, withImage: screenshot != nil).flatMap(SystemOne.answers)
    }

    static func body(_ state: SessionState, kinds: [TaskKind], screenshot: Data?) throws -> Data {
        try SystemOne.request(model: model, state: state, kinds: kinds, zeroRetention: zeroRetention, screenshot: screenshot)
    }

    /// The raw reply to a request body.
    func reply(to body: Data, withImage: Bool) async -> Result<Data, LabelError> {
        await GatewayHTTP.post(Self.url, key: key, headers: withImage ? ["TypeSafe-Danger-Zone-Images": "true"] : [:], body: body)
    }
}
