import Foundation
import JournalCore

/// One POST to the Vercel AI Gateway, shared by sorting and dictation. Retries busy and server errors, gives up on the rest.
enum GatewayHTTP {
    static func post(_ url: URL, key: String, headers: [String: String] = [:], body: Data, timeout: TimeInterval = 60) async -> Result<Data, LabelError> {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        var last = LabelError(message: "No reply.")
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1 << attempt)) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { continue }
            if status == 200 { return .success(data) }
            last = LabelError(message: "\(status) \(String(decoding: data.prefix(200), as: UTF8.self))")
            if status < 500 && status != 429 { break }
        }
        return .failure(last)
    }
}
