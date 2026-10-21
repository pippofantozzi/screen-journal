import Foundation

/// What to drop from one day so a stretch of time or a topic is gone from the journal.
public enum Forget {
    public enum Target: Equatable, Sendable {
        /// Half-open: `from` included, `to` excluded.
        case range(from: Date, to: Date)
        /// Every visit, event and session mentioning any of these, ignoring case and accents.
        case terms([String])
    }

    public struct Plan: Equatable, Sendable {
        public let frames: [FrameRecord]
        public let events: [EventRecord]
        public let sessions: [Session]
        public let deleteImages: [String]
        /// Earliest start to latest end of removed frames; can reach past the requested range.
        public let removedSpan: DateInterval?
        /// Kept frames and sessions that point at a deleted image.
        public let brokenReferences: Int
    }

    /// `imagesOnDisk` are paths relative to the day folder, like `FrameRecord.image`. Unreferenced ones whose
    /// capture time falls inside a removed row are orphans (crashes, skipped ticks) and go too.
    public static func plan(
        frames: [FrameRecord], events: [EventRecord], sessions: [Session], imagesOnDisk: [String], target: Target
    ) -> Plan {
        let removed = removedIndices(frames, target)
        let removedFrames = frames.indices.filter(removed.contains).map { frames[$0] }
        let keptFrames = frames.indices.filter { !removed.contains($0) }.map { frames[$0] }
        let keptSessions = sessions.filter { !forgets($0, target, removedFrames: removedFrames) }
        let referenced = images(frames, sessions)
        let orphans = imagesOnDisk.filter { !referenced.contains($0) && takenDuring(removedFrames, $0) }
        let doomed = Set(removedFrames.map(\.image))
            .union(referenced.subtracting(images(keptFrames, keptSessions)))
            .union(orphans)
        let keptReferences = keptFrames.map(\.image) + keptSessions.map(\.representativeFrame)
        return Plan(
            frames: keptFrames,
            events: events.filter { !forgets($0, target) },
            sessions: keptSessions,
            deleteImages: doomed.sorted(),
            removedSpan: span(removedFrames),
            brokenReferences: keptReferences.count(where: doomed.contains)
        )
    }

    private static func removedIndices(_ frames: [FrameRecord], _ target: Target) -> Set<Int> {
        switch target {
        case let .range(from, to):
            Set(frames.indices.filter { overlaps(frames[$0].start, frames[$0].end, from, to) })
        case let .terms(terms):
            Set(Visits.indices(frames).filter { $0.contains { mentions(frames[$0], terms) } }.joined())
        }
    }

    private static func forgets(_ event: EventRecord, _ target: Target) -> Bool {
        switch target {
        case let .range(from, to): from <= event.at && event.at < to
        case let .terms(terms): mentions([event.app, event.windowTitle, event.text], terms)
        }
    }

    private static func forgets(_ session: Session, _ target: Target, removedFrames: [FrameRecord]) -> Bool {
        switch target {
        case let .range(from, to):
            overlaps(session.start, session.end, from, to)
        case .terms:
            removedFrames.contains { f in
                f.focused && f.bundleID == session.bundleID && WindowTitle.stable(f.windowTitle) == session.windowTitle
                    && session.start <= f.end && f.start <= session.end
            }
        }
    }

    /// Whether [start, end] touches [from, to). A zero-length row counts at its start.
    private static func overlaps(_ start: Date, _ end: Date, _ from: Date, _ to: Date) -> Bool {
        start < to && (start >= from || end > from)
    }

    private static func mentions(_ frame: FrameRecord, _ terms: [String]) -> Bool {
        mentions([frame.app, frame.windowTitle, frame.text] + (frame.newLines ?? []), terms)
    }

    private static func mentions(_ fields: [String?], _ terms: [String]) -> Bool {
        fields.compactMap { $0 }.contains { field in
            terms.contains { field.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    private static func images(_ frames: [FrameRecord], _ sessions: [Session]) -> Set<String> {
        Set(frames.map(\.image) + sessions.map(\.representativeFrame))
    }

    /// Compares local times of day from names like `frames/HHMMSS-dN.heic` and row ids `HHMMSS-dN`, so no time zone is needed.
    private static func takenDuring(_ rows: [FrameRecord], _ image: String) -> Bool {
        guard let taken = secondOfDay(image) else { return false }
        return rows.contains { row in
            guard let start = secondOfDay(row.id) else { return false }
            return Double(start) <= Double(taken) && Double(taken) <= Double(start) + row.duration
        }
    }

    private static func secondOfDay(_ name: String) -> Int? {
        let hms = (name.split(separator: "/").last ?? "").prefix(6)
        guard hms.count == 6, hms.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(hms) else { return nil }
        return n / 10000 * 3600 + n / 100 % 100 * 60 + n % 100
    }

    private static func span(_ frames: [FrameRecord]) -> DateInterval? {
        guard let start = frames.map(\.start).min(), let end = frames.map(\.end).max() else { return nil }
        return DateInterval(start: start, end: end)
    }
}
