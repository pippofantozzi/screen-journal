import Foundation
import JournalCore

/// A hosted decision model behind the Vercel AI Gateway's System One endpoint.
/// The key comes from `AI_GATEWAY_API_KEY` in the environment, else the one saved in Settings; it is never stored in the journal.
struct DecisionGateway: Sendable {
    static let url = URL(string: "https://ai-gateway.vercel.sh/typesafe/v1/systemone")!
    /// 27B, answers a session's questions in under a second; `baseten/elephant-1` (9B) agreed on 93% of yes/no answers.
    static let model = "baseten/mammoth-1"
    /// Mammoth reads text only. Jev sees the screenshot too; pinned, since its image support is experimental and changes between versions.
    static let lookModel = "typesafe-ai/jev-1.14.0"
    /// Zero data retention needs the key's Vercel team on Pro; on Hobby the gateway refuses every request with 403.
    /// Prompt training is refused on every plan.
    static let zeroRetention = false
    static let keyName = "AI_GATEWAY_API_KEY"

    private let key: String

    /// The environment wins, so a developer's key overrides the saved one.
    static func configured() -> DecisionGateway? {
        let env = ProcessInfo.processInfo.environment[keyName].flatMap { $0.isEmpty ? nil : $0 }
        return (env ?? GatewayKey.read()).map(DecisionGateway.init)
    }

    init(key: String) {
        self.key = key
    }

    /// One throwaway question, so Settings can say whether the key works.
    func check() async -> Result<Void, LabelError> {
        await answers(.probe, kinds: TaskKind.defaults).map { _ in () }
    }

    /// Retries busy and server errors, gives up on the rest. With a screenshot, the vision model answers.
    func answers(_ state: SessionState, kinds: [TaskKind], screenshot: Data? = nil) async -> Result<SystemOne.Answers, LabelError> {
        var request = URLRequest(url: Self.url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if screenshot != nil { request.setValue("true", forHTTPHeaderField: "TypeSafe-Danger-Zone-Images") }
        do {
            request.httpBody = try SystemOne.request(model: screenshot == nil ? Self.model : Self.lookModel, state: state, kinds: kinds,
                                                     zeroRetention: Self.zeroRetention, screenshot: screenshot)
        } catch {
            return .failure(LabelError(message: error.localizedDescription))
        }
        var last = LabelError(message: "No reply.")
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1 << attempt)) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { continue }
            if status == 200 { return SystemOne.answers(data) }
            last = LabelError(message: "\(status) \(String(decoding: data.prefix(200), as: UTF8.self))")
            if status < 500 && status != 429 { break }
        }
        return .failure(last)
    }
}
