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
    /// Every sorted session with its answer, newest first, for looking at what was on screen.
    public let sorted: [Screen]

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
        sorted = sessions.compactMap { session in answered[session.start].map { Screen(session: session, label: $0) } }
            .sorted { $0.session.start > $1.session.start }
    }

    /// One sorted session, shown by its screenshot.
    public struct Screen: Equatable, Sendable {
        public let session: Session
        public let label: Label

        public init(session: Session, label: Label) {
            self.session = session
            self.label = label
        }

        /// The same measure as the bars: work Claude could probably take over.
        public var helpShare: Double { label.automatable * label.work }
        public var isLikely: Bool { helpShare >= 0.5 }
    }

    public enum Share: CaseIterable, Sendable {
        case any, likely, rest

        func admits(_ screen: Screen) -> Bool {
            switch self {
            case .any: true
            case .likely: screen.isLikely
            case .rest: !screen.isLikely
            }
        }
    }

    /// `task` nil for every task.
    public func screens(task: String?, share: Share) -> [Screen] {
        sorted.filter { (task == nil || $0.label.task == task) && share.admits($0) }
    }
}

extension Labeling.TaskTime {
    /// The share of all this task's time Claude could probably take over.
    public var helpShare: Double { seconds > 0 ? handoff / seconds : 0 }
}
