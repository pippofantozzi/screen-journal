import Foundation

public enum WeekDigest {
    /// A window that came back on more than one day.
    struct RecurringWindow: Equatable {
        let name: String
        let days: Int
        let seconds: TimeInterval
    }

    public static func markdown(_ days: [DayDigest], timeZone: TimeZone, limit: Int = 15) -> String {
        let days = days.sorted { $0.day < $1.day }
        guard let first = days.first, let last = days.last else { return "" }
        let active = days.reduce(0) { $0 + $1.activeSeconds }
        var lines = [
            "# Week of \(first.day) – \(last.day)",
            "",
            "Active: \(Format.clock(active)) across \(days.count) days.",
            "",
        ]
        let apps = days.flatMap(\.apps).merged()
        lines += ["## Time per app", ""] + apps.prefix(limit).map { "- \(Format.clock($0.seconds)) \($0.name)" } + [""]
        lines += ["## Recurring windows", ""]
        lines += recurringWindows(days).prefix(limit).map { "- \($0.days) days, \(Format.clock($0.seconds)) \($0.name)" }
        lines.append("")
        lines += ["## Frequent app switches", ""]
        lines += days.flatMap(\.transitions).merged().prefix(limit).map { "- \($0.count)× \($0.from) → \($0.to)" }
        lines.append("")
        let notedDays = days.filter { !$0.notes.isEmpty }
        if !notedDays.isEmpty {
            lines += ["## Notes", ""]
            for day in notedDays {
                lines += ["### \(day.day)", ""]
                lines += day.notes.map { "- \(Format.time($0.at, timeZone)) — \($0.text ?? "")" }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Windows seen on at least two days, most days first, then longest.
    static func recurringWindows(_ days: [DayDigest]) -> [RecurringWindow] {
        Dictionary(grouping: days.flatMap(\.windows), by: \.name)
            .filter { $0.value.count >= 2 }
            .map { RecurringWindow(name: $0.key, days: $0.value.count, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { ($0.days, $0.seconds, $1.name) > ($1.days, $1.seconds, $0.name) }
    }
}
