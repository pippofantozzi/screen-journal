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
    /// Switches between windows, named like `windows`. Shows ping-pong between tabs of one app.
    public let windowTransitions: [Transition]
    public let notes: [EventRecord]
}

extension DayDigest {
    /// Tolerates digests written before `windowTransitions` existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        activeSeconds = try c.decode(TimeInterval.self, forKey: .activeSeconds)
        sessionCount = try c.decode(Int.self, forKey: .sessionCount)
        apps = try c.decode([Total].self, forKey: .apps)
        windows = try c.decode([Total].self, forKey: .windows)
        transitions = try c.decode([Transition].self, forKey: .transitions)
        windowTransitions = try c.decodeIfPresent([Transition].self, forKey: .windowTransitions) ?? []
        notes = try c.decode([EventRecord].self, forKey: .notes)
    }
}

public enum DaySummary {
    public static func digest(day: String, sessions: [Session], events: [EventRecord]) -> DayDigest {
        DayDigest(
            day: day,
            activeSeconds: sessions.reduce(0) { $0 + $1.duration },
            sessionCount: sessions.count,
            apps: totals(sessions, by: appName),
            windows: totals(sessions, by: windowName),
            transitions: switches(sessions.map(appName)),
            windowTransitions: switches(sessions.map(windowName)),
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
        lines += ["## Frequent app switches", ""] + Format.switches(d.transitions, limit: limit) + [""]
        lines += ["## Frequent window switches", ""] + Format.switches(d.windowTransitions, limit: limit)
        return lines.joined(separator: "\n") + "\n"
    }

    /// One line for the rolling index.md.
    public static func indexLine(_ d: DayDigest) -> String {
        let top = d.apps.prefix(3).map(\.name).joined(separator: ", ")
        return "- [\(d.day)](days/\(d.day)/summary.md) — \(Format.clock(d.activeSeconds)) active, \(d.notes.count) notes — \(top)"
    }

    private static func appName(_ s: Session) -> String { s.app ?? "Unknown" }

    private static func windowName(_ s: Session) -> String {
        [appName(s), s.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private static func totals(_ sessions: [Session], by key: (Session) -> String) -> [DayDigest.Total] {
        sessions.map { DayDigest.Total(name: key($0), seconds: $0.duration) }.merged()
    }

    /// Consecutive names that differ, counted per pair.
    private static func switches(_ names: [String]) -> [DayDigest.Transition] {
        zip(names, names.dropFirst())
            .filter { $0 != $1 }
            .map { DayDigest.Transition(from: $0, to: $1, count: 1) }
            .merged()
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

    static func switches(_ transitions: [DayDigest.Transition], limit: Int) -> [String] {
        transitions.prefix(limit).map { "- \($0.count)× \($0.from) → \($0.to)" }
    }
}
