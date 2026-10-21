import Foundation
import Testing
@testable import JournalCore

/// Back-to-back focused records, one per duration, alternating between two windows unless `titles` or `title` say otherwise.
private func records(_ durations: [TimeInterval], lines: [Int]? = nil, title: String? = nil, titles: [String]? = nil) -> [FrameRecord] {
    var start = base
    return durations.enumerated().map { i, d in
        defer { start += d }
        let text = (0..<(lines?[i] ?? 0)).map { "line \(i).\($0)" }
        return FrameRecord(
            id: "\(i)", start: start, end: start + d, display: 1, focused: true, app: "App", bundleID: "id.app",
            windowTitle: titles?[i] ?? title ?? "w\(i % 2)", image: "frames/\(i).heic", text: nil, newLines: text.isEmpty ? nil : text
        )
    }
}

struct IntervalAdviceTests {
    let candidates: [TimeInterval] = [5, 10, 15, 30, 60]

    @Test func learnsUntilThreeHoursOfFocusedTime() {
        let advice = IntervalAdvice.advise(records(Array(repeating: 60, count: 120)), current: 10, candidates: candidates)
        #expect(advice == .learning(have: 7200, need: 3 * 3600))
    }

    @Test func ignoresUnfocusedRecords() {
        let unfocused = records(Array(repeating: 600, count: 30)).map {
            FrameRecord(id: $0.id, start: $0.start, end: $0.end, display: 2, focused: false, app: nil, bundleID: nil,
                        windowTitle: nil, image: $0.image, text: nil, newLines: nil)
        }
        #expect(IntervalAdvice.advise(unfocused, current: 10, candidates: candidates) == .learning(have: 0, need: 3 * 3600))
    }

    @Test func longDwellsThatSaveNoWorkKeepTheCurrentInterval() {
        let advice = IntervalAdvice.advise(records(Array(repeating: 100, count: 120)), current: 10, candidates: candidates)
        #expect(advice == .keep(10))
    }

    @Test func longDwellsMixedWithMediumOnesSuggestTheLargestCandidateMeetingEveryBar() {
        // One window: 600 s stretches with 10 lines each, between 20 s ones with 1 line each.
        let durations = (0..<40).map { $0 % 2 == 0 ? 600.0 : 20 }
        let lines = (0..<40).map { $0 % 2 == 0 ? 10 : 1 }
        // 60 s drops text coverage to (200 + 20/3) / 220 ≈ 0.94; 30 s keeps 0.97 and saves 1/6.
        guard case .suggest(30, 1, let text, let saved) = IntervalAdvice.advise(
            records(durations, lines: lines, title: "Doc"), current: 10, candidates: candidates
        ) else {
            Issue.record("expected a 30 s suggestion")
            return
        }
        #expect(abs(text - (200 + 20 * 20 / 30.0) / 220) < 1e-9)
        #expect(abs(saved - 1 / 6.0) < 1e-9)
    }

    @Test func suggestsAtExactlyTheSavingsFloorAndNotBelowIt() {
        // One window: instants that a 20 s interval would skip, among long stretches it keeps.
        let atFloor = records(Array(repeating: 0, count: 3) + Array(repeating: 640, count: 17), title: "Doc")
        let below = records(Array(repeating: 0, count: 3) + Array(repeating: 640, count: 18), title: "Doc")
        guard case .suggest(20, 1, 1, let saved) = IntervalAdvice.advise(atFloor, current: 10, candidates: [20]) else {
            Issue.record("expected a 20 s suggestion")
            return
        }
        #expect(abs(saved - 0.15) < 1e-9)
        #expect(IntervalAdvice.advise(below, current: 10, candidates: [20]) == .keep(10))
    }

    @Test func quickSwitchesKeepTheCurrentInterval() {
        let advice = IntervalAdvice.advise(records(Array(repeating: 10, count: 1200)), current: 10, candidates: candidates)
        #expect(advice == .keep(10))
    }

    @Test func textCoverageWeighsRecordsByTheLinesTheyAdded() {
        // One long visit: 100 one-minute records, then 100 ten-second records.
        let durations = Array(repeating: 60.0, count: 100) + Array(repeating: 10.0, count: 100) + [8000]
        let wordyQuick = records(durations, lines: Array(repeating: 1, count: 100) + Array(repeating: 9, count: 100) + [0], title: "Doc")
        let wordySlow = records(durations, lines: Array(repeating: 9, count: 100) + Array(repeating: 1, count: 100) + [0], title: "Doc")

        #expect(IntervalAdvice.advise(wordyQuick, current: 10, candidates: [15]) == .keep(10))
        guard case .suggest(15, 1, let text, let saved) = IntervalAdvice.advise(wordySlow, current: 10, candidates: [15]) else {
            Issue.record("expected a suggestion")
            return
        }
        #expect(abs(text - (900 + 100 * 10 / 15) / 1000) < 1e-9)
        #expect(abs(saved - (100 * (1 - 10 / 15.0)) / 201) < 1e-9)
    }

    @Test func suggestsAtExactlyTheCoverageBarAndNotBelowIt() {
        // Long visits made of a 600 s stretch and three 1 s blips (the blips are the work saved), then one instant visit.
        func visits(_ long: Int) -> [FrameRecord] {
            let durations: [TimeInterval] = (0..<long).flatMap { _ in [600, 1, 1, 1] } + [0]
            let titles = (0..<long).flatMap { i in Array(repeating: "w\(i)", count: 4) } + ["instant"]
            return records(durations, titles: titles)
        }
        guard case .suggest(15, let covered, 1, _) = IntervalAdvice.advise(visits(19), current: 10, candidates: [15]) else {
            Issue.record("expected a 15 s suggestion")
            return
        }
        #expect(covered == 0.95)
        #expect(IntervalAdvice.advise(visits(18), current: 10, candidates: [15]) == .keep(10))
    }

    @Test func onlyConsidersLongerIntervals() {
        let advice = IntervalAdvice.advise(records(Array(repeating: 100, count: 120)), current: 60, candidates: candidates)
        #expect(advice == .keep(60))
    }
}
