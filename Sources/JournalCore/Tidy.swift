/// Which screenshots a finished day can lose while staying readable:
/// it keeps each session's representative image, each note's image and the first image of every visit.
public enum Tidy {
    public enum Plan: Equatable, Sendable {
        case delete([String])
        /// The day's rows look incomplete, so deleting would be guessing.
        case refused(String)
    }

    /// `imagesOnDisk` are paths relative to the day folder, like `FrameRecord.image`.
    public static func plan(frames: [FrameRecord], sessions: [Session], notes: [EventRecord], imagesOnDisk: [String]) -> Plan {
        if imagesOnDisk.isEmpty { return .delete([]) }
        if frames.isEmpty { return .refused("No frames for this day, so every image would look unused.") }
        if sessions.isEmpty { return .refused("No sessions for this day, so representative images are unknown.") }
        let keep = keptImages(frames: frames, sessions: sessions, notes: notes)
        if keep.isEmpty { return .refused("Nothing would be kept.") }
        return .delete(Set(imagesOnDisk).subtracting(keep).sorted())
    }

    private static func keptImages(frames: [FrameRecord], sessions: [Session], notes: [EventRecord]) -> Set<String> {
        let imageByFrameID = Dictionary(frames.map { ($0.id, $0.image) }, uniquingKeysWith: { first, _ in first })
        return Set(sessions.map(\.representativeFrame))
            .union(notes.compactMap { $0.frameID.flatMap { imageByFrameID[$0] } })
            .union(Visits.indices(frames).compactMap { $0.first.map { frames[$0].image } })
    }
}
