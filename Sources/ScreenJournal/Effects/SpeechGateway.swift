import Foundation
import JournalCore

/// Dictation's two hosted models behind the Vercel AI Gateway: one hears, one writes. Both keep nothing.
struct SpeechGateway: Sendable {
    static let transcriptionURL = URL(string: "https://ai-gateway.vercel.sh/v4/ai/transcription-model")!
    static let chatURL = URL(string: "https://ai-gateway.vercel.sh/v1/chat/completions")!
    /// About 1.4 s for a short clip, steadily; told the language, or left to detect it.
    static let transcriptionModel = "mistral/voxtral-small-transcribe-3"
    /// Small and fast; routed to the provider with the most tokens per second.
    static let writeModel = "deepseek/deepseek-v4.1-flash-1017"
    static let zeroRetention = true

    private let key: String

    static func configured() -> SpeechGateway? {
        GatewayKey.current().map(SpeechGateway.init)
    }

    init(key: String) {
        self.key = key
    }

    /// Empty when nothing was said.
    func transcribe(wav: Data, words: [String], language: DictationLanguage) async -> Result<String, LabelError> {
        let body: Data
        do { body = try Transcription.request(wav: wav, words: words, language: language, zeroRetention: Self.zeroRetention) } catch { return .failure(LabelError(message: error.localizedDescription)) }
        let headers = [
            "ai-gateway-protocol-version": "0.0.1",
            "ai-transcription-model-specification-version": "4",
            "ai-model-id": Self.transcriptionModel,
        ]
        return await GatewayHTTP.post(Self.transcriptionURL, key: key, headers: headers, body: body).flatMap(Transcription.text)
    }

    func rewrite(_ intent: DictationIntent, transcript: String, words: [String]) async -> Result<String, LabelError> {
        let body: Data
        do {
            body = try Rewrite.request(model: Self.writeModel, intent: intent, transcript: transcript, words: words, zeroRetention: Self.zeroRetention)
        } catch { return .failure(LabelError(message: error.localizedDescription)) }
        return await GatewayHTTP.post(Self.chatURL, key: key, body: body, timeout: 30).flatMap(Rewrite.text)
    }
}
