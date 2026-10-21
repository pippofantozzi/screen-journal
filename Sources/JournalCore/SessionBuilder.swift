import Foundation

public enum SessionBuilder {
    /// Folds focused frames into runs of the same app and window, by stable title (spinners and counters dropped).
    /// The representative frame is the one that stayed on screen longest.
    public static func sessions(from frames: [FrameRecord], maxGap: TimeInterval = 60) -> [Session] {
        var sessions: [Session] = []
        var longest: TimeInterval = 0
        for frame in frames.filter(\.focused).sorted(by: { $0.start < $1.start }) {
            let title = WindowTitle.stable(frame.windowTitle)
            if var last = sessions.last,
               last.bundleID == frame.bundleID, last.windowTitle == title,
               frame.start.timeIntervalSince(last.end) <= maxGap {
                last.end = max(last.end, frame.end)
                last.frames += 1
                if frame.duration > longest {
                    longest = frame.duration
                    last.representativeFrame = frame.image
                }
                sessions[sessions.count - 1] = last
            } else {
                longest = frame.duration
                sessions.append(Session(
                    start: frame.start, end: frame.end, app: frame.app, bundleID: frame.bundleID,
                    windowTitle: title, frames: 1, representativeFrame: frame.image
                ))
            }
        }
        return sessions
    }
}
