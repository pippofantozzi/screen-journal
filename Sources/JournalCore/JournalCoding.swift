import Foundation

/// JSONL with local-time ISO dates, so both humans and `rg` can read timestamps.
public enum JournalCoding {
    public static func line<T: Encodable>(_ value: T, timeZone: TimeZone) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func decodeLines<T: Decodable>(_ type: T.Type, from text: String) throws -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try text.split(separator: "\n").map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }
}
