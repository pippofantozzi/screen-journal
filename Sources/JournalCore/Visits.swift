/// A visit is one stay in one window on one display: it starts at a window change or a row carrying full OCR `text`,
/// and runs over the following rows whose `newLines` only add to what was already on screen.
public enum Visits {
    /// Indices into `frames`, one array per visit, each in time order.
    public static func indices(_ frames: [FrameRecord]) -> [[Int]] {
        var visits: [[Int]] = []
        var openVisit: [Int: Int] = [:]
        for i in frames.indices.sorted(by: { (frames[$0].start, $0) < (frames[$1].start, $1) }) {
            let frame = frames[i]
            if let v = openVisit[frame.display], let last = visits[v].last, !startsVisit(frame, after: frames[last]) {
                visits[v].append(i)
            } else {
                openVisit[frame.display] = visits.count
                visits.append([i])
            }
        }
        return visits
    }

    private static func startsVisit(_ frame: FrameRecord, after previous: FrameRecord) -> Bool {
        frame.text != nil || frame.bundleID != previous.bundleID || frame.windowTitle != previous.windowTitle
    }
}
