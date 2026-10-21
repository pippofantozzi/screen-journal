import Foundation

public struct DayDigest: Codable, Equatable, Sendable {
    public struct Total: Codable, Equatable, Sendable {
        public let name: String
        public let seconds: TimeInterval
    }

    public struct Transition: Codable, Equatable, Sendable {
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
            .map { DayDigest.Transition(from: $0, to: $1, count: 1) }

        return DayDigest(
            day: day,
            activeSeconds: sessions.reduce(0) { $0 + $1.duration },
            sessionCount: sessions.count,
            apps: totals(sessions) { $0.app ?? "Unknown" },
            windows: totals(sessions) { s in
                [s.app ?? "Unknown", s.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            },
            transitions: transitions.merged(),
            notes: events.filter { $0.kind == .note }
        )
    }

    public static func markdown(_ d: DayDigest, timeZone: TimeZone, limit: Int = 15) -> String {
        var lines = [
            "# \(d.day)",
            "",
            "Active: \(Format.clock(d.activeSeconds)) across \(d.sessionCount) sessions.",
            "",
        ]
        if !d.notes.isEmpty {
            lines += ["## Notes she left", ""]
            lines += d.notes.map { "- \(Format.time($0.at, timeZone)) — \($0.text ?? "")" }
            lines.append("")
        }
        lines += ["## Time per app", ""] + d.apps.prefix(limit).map { "- \(Format.clock($0.seconds)) \($0.name)" } + [""]
        lines += ["## Top windows", ""] + d.windows.prefix(limit).map { "- \(Format.clock($0.seconds)) \($0.name)" } + [""]
        lines += ["## Frequent app switches", ""]
        lines += d.transitions.prefix(limit).map { "- \($0.count)× \($0.from) → \($0.to)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line for the rolling index.md.
    public static func indexLine(_ d: DayDigest) -> String {
        let top = d.apps.prefix(3).map(\.name).joined(separator: ", ")
        return "- [\(d.day)](days/\(d.day)/summary.md) — \(Format.clock(d.activeSeconds)) active, \(d.notes.count) notes — \(top)"
    }

    private static func totals(_ sessions: [Session], by key: (Session) -> String) -> [DayDigest.Total] {
        sessions.map { DayDigest.Total(name: key($0), seconds: $0.duration) }.merged()
    }
}

extension [DayDigest.Total] {
    /// One total per name, longest first.
    func merged() -> [DayDigest.Total] {
        Dictionary(grouping: self, by: \.name)
            .map { DayDigest.Total(name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
    }
}

extension [DayDigest.Transition] {
    /// One count per from→to pair, most frequent first.
    func merged() -> [DayDigest.Transition] {
        Dictionary(grouping: self) { "\($0.from)→\($0.to)" }
            .values
            .map { DayDigest.Transition(from: $0[0].from, to: $0[0].to, count: $0.reduce(0) { $0 + $1.count }) }
            .sorted { ($0.count, $1.from + $1.to) > ($1.count, $0.from + $0.to) }
    }
}

/// Shared markdown formatting for day and week summaries.
enum Format {
    static func clock(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }

    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
