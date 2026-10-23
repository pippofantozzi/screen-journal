import Foundation

/// What the "Your week" window shows: where the seven days ending on a day went, by task,
/// and the few windows Claude could most likely take off her hands.
public struct WeekReport: Equatable, Sendable {
    public let first: String
    public let last: String
    public let tracked: TimeInterval
    /// Time in sessions no answer stands for yet, so the totals never pretend to be complete.
    public let unsorted: TimeInterval
    public let tasks: [Labeling.TaskTime]
    public let candidates: [Labeling.Candidate]

    /// A suggestion has to save at least a minute to be worth showing.
    static let worthwhile: TimeInterval = 60
    static let suggestions = 3

    public static func days(endingOn day: String) -> [String] {
        (-6...0).compactMap { DayName.adding($0, to: day) }
    }

    public init(endingOn day: String, sessions: [Session], labels: [Label], def: String) {
        first = DayName.adding(-6, to: day) ?? day
        last = day
        tracked = sessions.reduce(0) { $0 + $1.duration }
        let answered = Labeling.current(labels, def: def)
        unsorted = sessions.filter { answered[$0.start] == nil }.reduce(0) { $0 + $1.duration }
        tasks = Labeling.tasks(sessions: sessions, labels: labels, def: def)
        candidates = Array(Labeling.candidates(sessions: sessions, labels: labels, def: def)
            .filter { $0.handoff >= Self.worthwhile }
            .prefix(Self.suggestions))
    }
}

extension Labeling.TaskTime {
    /// The share of all this task's time Claude could probably take over.
    public var helpShare: Double { seconds > 0 ? handoff / seconds : 0 }
}
