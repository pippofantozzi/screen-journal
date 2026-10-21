import Foundation

/// A moment expressed in the user's local calendar: which day folder, which frame name.
public struct DayStamp: Equatable, Sendable {
    public let string: String
    private let hms: String

    public init(_ date: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        string = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        hms = String(format: "%02d%02d%02d", c.hour!, c.minute!, c.second!)
    }

    public func frameID(display: Int) -> String { "\(hms)-d\(display)" }
}

public enum RetentionPolicy {
    /// Day folders older than the last `keep` days (today included).
    public static func expiredDays(_ names: [String], today: String, keep: Int) -> [String] {
        guard let todayDate = parse(today),
              let cutoff = utc.date(byAdding: .day, value: -(keep - 1), to: todayDate) else { return [] }
        return names.filter { name in parse(name).map { $0 < cutoff } ?? false }.sorted()
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func parse(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard day.count == 10, parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
