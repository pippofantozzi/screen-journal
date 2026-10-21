import Foundation

/// JSONL with local-time ISO dates, so both humans and `rg` can read timestamps.
public enum JournalCoding {
    public static func line<T: Encodable>(_ value: T, timeZone: TimeZone) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Same text as ISO8601DateFormatter ("2026-10-21T19:28:12-03:00"), but a Sendable value.
        let style = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decodeLines<T: Decodable>(_ type: T.Type, from text: String) throws -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text.split(separator: "\n").map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }
}
