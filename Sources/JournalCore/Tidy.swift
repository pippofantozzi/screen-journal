/// Which screenshots a finished day can lose while staying readable:
/// it keeps each session's representative image, each note's image and the first image of every visit.
public enum Tidy {
    public enum Plan: Equatable, Sendable {
        /// Images to delete, and every frame row with deleted images replaced by the previous image in its visit.
        case slim(delete: [String], frames: [FrameRecord])
        /// The day's rows look incomplete, so deleting would be guessing.
        case refused(String)
    }

    /// `imagesOnDisk` are paths relative to the day folder, like `FrameRecord.image`.
    public static func plan(frames: [FrameRecord], sessions: [Session], notes: [EventRecord], imagesOnDisk: [String]) -> Plan {
        if imagesOnDisk.isEmpty { return .slim(delete: [], frames: frames) }
        if frames.isEmpty { return .refused("No frames for this day, so every image would look unused.") }
        if sessions.isEmpty { return .refused("No sessions for this day, so representative images are unknown.") }
        let keep = keptImages(frames: frames, sessions: sessions, notes: notes)
        if keep.isEmpty { return .refused("Nothing would be kept.") }
        let doomed = Set(imagesOnDisk).subtracting(keep)
        return .slim(delete: doomed.sorted(), frames: repointed(frames, away: doomed))
    }

    private static func keptImages(frames: [FrameRecord], sessions: [Session], notes: [EventRecord]) -> Set<String> {
        let imageByFrameID = Dictionary(frames.map { ($0.id, $0.image) }, uniquingKeysWith: { first, _ in first })
        return Set(sessions.map(\.representativeFrame))
            .union(notes.compactMap { $0.frameID.flatMap { imageByFrameID[$0] } })
            .union(Visits.indices(frames).compactMap { $0.first.map { frames[$0].image } })
    }

    /// A visit's first image is always kept, so every doomed row has an earlier image to fall back on.
    private static func repointed(_ frames: [FrameRecord], away doomed: Set<String>) -> [FrameRecord] {
        var result = frames
        for visit in Visits.indices(frames) {
            for (previous, i) in zip(visit, visit.dropFirst()) where doomed.contains(result[i].image) {
                result[i] = result[i].pointing(at: result[previous].image)
            }
        }
        return result
    }
}
