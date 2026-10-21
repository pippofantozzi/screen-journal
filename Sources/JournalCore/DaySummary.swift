import Foundation

public struct DayDigest: Equatable, Sendable {
    public struct Total: Equatable, Sendable {
        public let name: String
        public let seconds: TimeInterval
    }

    public struct Transition: Equatable, Sendable {
        public let from: String
        public let to: String
        public let count: Int
    }

    public let day: String
    public let activeSeconds: TimeInterval
    public let sessionCount: Int
    public let apps: [Total]
    public let windows: [Total]
    public let transitions: [Transition]
    public let notes: [EventRecord]
}

public enum DaySummary {
    public static func digest(day: String, sessions: [Session], events: [EventRecord]) -> DayDigest {
        let appNames = sessions.map { $0.app ?? "Unknown" }
        let transitions = zip(appNames, appNames.dropFirst())
            .filter { $0 != $1 }
            .reduce(into: [String: (String, String, Int)]()) { acc, pair in
                acc["\(pair.0)→\(pair.1)", default: (pair.0, pair.1, 0)].2 += 1
            }
            .values
            .map { DayDigest.Transition(from: $0.0, to: $0.1, count: $0.2) }
            .sorted { ($0.count, $1.from + $1.to) > ($1.count, $0.from + $0.to) }

        return DayDigest(
            day: day,
            activeSeconds: sessions.reduce(0) { $0 + $1.duration },
            sessionCount: sessions.count,
            apps: totals(sessions) { $0.app ?? "Unknown" },
            windows: totals(sessions) { s in
                [s.app ?? "Unknown", s.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            },
            transitions: transitions,
            notes: events.filter { $0.kind == .note }
        )
    }

    public static func markdown(_ d: DayDigest, timeZone: TimeZone, limit: Int = 15) -> String {
        var lines = [
            "# \(d.day)",
            "",
            "Active: \(clock(d.activeSeconds)) across \(d.sessionCount) sessions.",
            "",
        ]
        if !d.notes.isEmpty {
            lines += ["## Notes she left", ""]
            lines += d.notes.map { "- \(time($0.at, timeZone)) — \($0.text ?? "")" }
            lines.append("")
        }
        lines += ["## Time per app", ""] + d.apps.prefix(limit).map { "- \(clock($0.seconds)) \($0.name)" } + [""]
        lines += ["## Top windows", ""] + d.windows.prefix(limit).map { "- \(clock($0.seconds)) \($0.name)" } + [""]
        lines += ["## Frequent app switches", ""]
        lines += d.transitions.prefix(limit).map { "- \($0.count)× \($0.from) → \($0.to)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line for the rolling index.md.
    public static func indexLine(_ d: DayDigest) -> String {
        let top = d.apps.prefix(3).map(\.name).joined(separator: ", ")
        return "- [\(d.day)](days/\(d.day)/summary.md) — \(clock(d.activeSeconds)) active, \(d.notes.count) notes — \(top)"
    }

    private static func totals(_ sessions: [Session], by key: (Session) -> String) -> [DayDigest.Total] {
        Dictionary(grouping: sessions, by: key)
            .map { DayDigest.Total(name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }

    private static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
