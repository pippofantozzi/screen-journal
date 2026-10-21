import Foundation

/// Whether a longer capture interval would still catch what she does, judged by how long her screens actually last.
/// A screen state lasting `d` is caught at interval `I` with probability min(1, d/I): an expected value, no replay.
public enum IntervalAdvice: Equatable, Sendable {
    /// Not enough focused time yet to judge.
    case learning(have: TimeInterval, need: TimeInterval)
    case keep(TimeInterval)
    /// Expected share of window visits and of text still caught, and of records (OCR runs) no longer needed.
    case suggest(TimeInterval, visits: Double, text: Double, savedWork: Double)

    public static let need: TimeInterval = 3 * 3600
    public static let bar = 0.95
    /// A longer interval that barely saves work isn't worth suggesting; an unchanged tick is nearly free.
    public static let minSavedWork = 0.15

    /// The largest candidate above `current` that keeps visit and text coverage at or above `bar`
    /// and saves at least `minSavedWork`.
    public static func advise(_ frames: [FrameRecord], current: TimeInterval, candidates: [TimeInterval]) -> IntervalAdvice {
        let focused = frames.filter(\.focused).sorted { $0.start < $1.start }
        let have = focused.reduce(0) { $0 + $1.duration }
        guard have >= need else { return .learning(have: have, need: need) }

        let visits = visitDurations(focused)
        let lines = focused.map { Double(lineCount($0)) }
        for interval in candidates.filter({ $0 > current }).sorted(by: >) {
            let caught = { (d: TimeInterval) in min(1, max(0, d) / interval) }
            let visitCoverage = mean(visits.map(caught))
            let textCoverage = weightedMean(focused.map { caught($0.duration) }, weights: lines)
            let savedWork = 1 - mean(focused.map { caught($0.duration) })
            guard visitCoverage >= bar, textCoverage >= bar, savedWork >= minSavedWork else { continue }
            return .suggest(interval, visits: visitCoverage, text: textCoverage, savedWork: savedWork)
        }
        return .keep(current)
    }

    /// Runs of consecutive records in the same window, as total time on screen.
    static func visitDurations(_ records: [FrameRecord]) -> [TimeInterval] {
        var visits: [(key: [String?], seconds: TimeInterval)] = []
        for r in records {
            let key = [r.bundleID, r.windowTitle]
            if visits.last?.key == key {
                visits[visits.count - 1].seconds += r.duration
            } else {
                visits.append((key, r.duration))
            }
        }
        return visits.map(\.seconds)
    }

    /// Lines the record added to the journal: its full text, or its new lines.
    static func lineCount(_ r: FrameRecord) -> Int {
        r.text.map { TextDelta.lineSet($0).count } ?? r.newLines?.count ?? 0
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 1 : values.reduce(0, +) / Double(values.count)
    }

    /// 1 when nothing carries weight: no text means no text to miss.
    private static func weightedMean(_ values: [Double], weights: [Double]) -> Double {
        let total = weights.reduce(0, +)
        return total == 0 ? 1 : zip(values, weights).reduce(0) { $0 + $1.0 * $1.1 } / total
    }
}
