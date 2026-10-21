import Foundation
import CoreGraphics
import Testing
@testable import JournalCore

let rome = TimeZone(identifier: "Europe/Rome")!
let base = Date(timeIntervalSince1970: 1_792_000_000) // fixed instant

func frame(_ id: String, at offset: TimeInterval, for duration: TimeInterval, app: String, title: String? = nil, focused: Bool = true) -> FrameRecord {
    FrameRecord(
        id: id, start: base + offset, end: base + offset + duration,
        display: 1, focused: focused, app: app, bundleID: "id.\(app)", windowTitle: title,
        image: "frames/\(id).heic", text: nil, newLines: nil
    )
}

struct SessionBuilderTests {
    @Test func mergesConsecutiveFramesOfSameWindow() {
        let frames = [
            frame("a", at: 0, for: 10, app: "Mail", title: "Inbox"),
            frame("b", at: 10, for: 50, app: "Mail", title: "Inbox"),
        ]
        let sessions = SessionBuilder.sessions(from: frames)
        #expect(sessions.count == 1)
        #expect(sessions[0].frames == 2)
        #expect(sessions[0].end == base + 60)
        #expect(sessions[0].representativeFrame == "frames/b.heic")
    }

    @Test func splitsOnWindowChange() {
        let frames = [
            frame("a", at: 0, for: 10, app: "Mail", title: "Inbox"),
            frame("b", at: 10, for: 10, app: "Mail", title: "Draft"),
        ]
        #expect(SessionBuilder.sessions(from: frames).map(\.windowTitle) == ["Inbox", "Draft"])
    }

    @Test func splitsOnGapLongerThanMaxGap() {
        let frames = [
            frame("a", at: 0, for: 10, app: "Mail"),
            frame("b", at: 200, for: 10, app: "Mail"),
        ]
        #expect(SessionBuilder.sessions(from: frames, maxGap: 60).count == 2)
    }

    @Test func ignoresUnfocusedDisplays() {
        let frames = [
            frame("a", at: 0, for: 10, app: "Mail"),
            frame("b", at: 0, for: 10, app: "Slack", focused: false),
        ]
        #expect(SessionBuilder.sessions(from: frames).map(\.app) == ["Mail"])
    }

    @Test func sortsUnorderedInput() {
        let frames = [
            frame("b", at: 10, for: 10, app: "Slack"),
            frame("a", at: 0, for: 10, app: "Mail"),
        ]
        #expect(SessionBuilder.sessions(from: frames).map(\.app) == ["Mail", "Slack"])
    }
}

struct DaySummaryTests {
    @Test func countsWindowSwitchesWithinOneApp() {
        let sessions = SessionBuilder.sessions(from: [
            frame("a", at: 0, for: 10, app: "Chrome", title: "CRM"),
            frame("b", at: 10, for: 10, app: "Chrome", title: "Bank"),
            frame("c", at: 20, for: 10, app: "Chrome", title: "CRM"),
            frame("d", at: 30, for: 10, app: "Chrome", title: "Bank"),
        ])
        let digest = DaySummary.digest(day: "d", sessions: sessions, events: [])
        #expect(digest.transitions.isEmpty)
        #expect(digest.windowTransitions.first == .init(from: "Chrome — CRM", to: "Chrome — Bank", count: 2))
        #expect(digest.windowTransitions.map(\.count).reduce(0, +) == 3)
        #expect(DaySummary.markdown(digest, timeZone: rome).contains("## Frequent window switches\n\n- 2× Chrome — CRM → Chrome — Bank"))
    }

    @Test func totalsTimePerAppAndWindowLongestFirst() {
        let sessions = SessionBuilder.sessions(from: [
            frame("a", at: 0, for: 60, app: "Mail", title: "Inbox"),
            frame("b", at: 60, for: 600, app: "Excel", title: "Budget.xlsx"),
            frame("c", at: 660, for: 120, app: "Mail", title: "Inbox"),
        ])
        let digest = DaySummary.digest(day: "2026-10-21", sessions: sessions, events: [])
        #expect(digest.activeSeconds == 780)
        #expect(digest.apps.map(\.name) == ["Excel", "Mail"])
        #expect(digest.apps.map(\.seconds) == [600, 180])
        #expect(digest.windows.first?.name == "Excel — Budget.xlsx")
    }

    @Test func countsAppTransitionsBothWays() {
        let sessions = SessionBuilder.sessions(from: [
            frame("a", at: 0, for: 10, app: "Mail"),
            frame("b", at: 10, for: 10, app: "Excel"),
            frame("c", at: 20, for: 10, app: "Mail"),
            frame("d", at: 30, for: 10, app: "Excel"),
        ])
        let digest = DaySummary.digest(day: "d", sessions: sessions, events: [])
        #expect(digest.transitions.first == .init(from: "Mail", to: "Excel", count: 2))
    }

    @Test func markdownIncludesNotes() {
        let note = EventRecord(at: base, kind: .note, text: "this export is tedious")
        let digest = DaySummary.digest(day: "2026-10-21", sessions: [], events: [note])
        let md = DaySummary.markdown(digest, timeZone: rome)
        #expect(md.contains("this export is tedious"))
        #expect(md.hasPrefix("# 2026-10-21"))
    }
}

struct RetentionPolicyTests {
    @Test func deletesDaysOlderThanKeepWindow() {
        let days = ["2026-09-20", "2026-09-21", "2026-09-22", "2026-10-21"]
        let expired = RetentionPolicy.expiredDays(days, today: "2026-10-21", keep: 30)
        #expect(expired == ["2026-09-20", "2026-09-21"])
    }

    @Test func ignoresNonDayFolders() {
        #expect(RetentionPolicy.expiredDays(["notes", ".DS_Store"], today: "2026-10-21", keep: 1).isEmpty)
    }

    @Test func handlesDSTTransitionWeekend() {
        // Europe switches back on 2026-10-25; day math must not drift.
        let expired = RetentionPolicy.expiredDays(["2026-10-24", "2026-10-25", "2026-10-26"], today: "2026-10-27", keep: 2)
        #expect(expired == ["2026-10-24", "2026-10-25"])
    }
}

struct DayStampTests {
    @Test func usesLocalCalendarDay() {
        // 23:30 UTC on Oct 21 is already Oct 22 in Rome.
        let late = ISO8601DateFormatter().date(from: "2026-10-21T23:30:00Z")!
        #expect(DayStamp(late, in: rome).string == "2026-10-22")
        #expect(DayStamp(late, in: rome).frameID(display: 2) == "013000-d2")
    }
}

struct WindowPlacementTests {
    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)

    func window(_ app: String, _ bounds: CGRect, layer: Int = 0, bundleID: String? = nil) -> WindowInfo {
        WindowInfo(app: app, bundleID: bundleID, title: nil, bounds: bounds, layer: layer)
    }

    @Test func picksFrontmostNormalWindowCenteredOnDisplay() {
        let windows = [
            window("Menubar", CGRect(x: 0, y: 0, width: 2000, height: 24), layer: 25),
            window("Slack", CGRect(x: 1100, y: 100, width: 600, height: 500)),
            window("Mail", CGRect(x: 100, y: 100, width: 600, height: 500)),
        ]
        #expect(WindowPlacement.topWindow(on: left, among: windows)?.app == "Mail")
        #expect(WindowPlacement.topWindow(on: right, among: windows)?.app == "Slack")
    }

    @Test func ignoresTinyWindows() {
        let windows = [window("Tooltip", CGRect(x: 10, y: 10, width: 20, height: 20)), window("Mail", left)]
        #expect(WindowPlacement.topWindow(on: left, among: windows)?.app == "Mail")
    }

    @Test func skipsSystemDialogsAboveRealWindows() {
        let windows = [
            window("universalAccessAuthWarn", CGRect(x: 350, y: 300, width: 300, height: 150)),
            window("Ghostty", left, bundleID: "com.mitchellh.ghostty"),
        ]
        #expect(WindowPlacement.topWindow(on: left, among: windows)?.app == "Ghostty")
    }

    @Test func skipsOwnWindows() {
        let windows = [window("Screen Journal", left, bundleID: "me.journal"), window("Mail", left)]
        #expect(WindowPlacement.topWindow(on: left, among: windows, ownBundleID: "me.journal")?.app == "Mail")
    }

    @Test func prefersFrontmostAppsWindowOnThatDisplay() {
        let windows = [
            window("Slack", CGRect(x: 100, y: 100, width: 300, height: 300), bundleID: "com.tinyspeck.slackmacgap"),
            window("Mail", left, bundleID: "com.apple.mail"),
        ]
        #expect(WindowPlacement.topWindow(on: left, among: windows, preferring: "com.apple.mail")?.app == "Mail")
        #expect(WindowPlacement.topWindow(on: left, among: windows, preferring: "com.other")?.app == "Slack")
    }
}

struct SystemAppsTests {
    @Test func matchesByNameOrBundleIDOrSelf() {
        #expect(SystemApps.isIgnored(app: "SecurityAgent", bundleID: nil, ownBundleID: nil))
        #expect(SystemApps.isIgnored(app: "Whatever", bundleID: "com.apple.dock", ownBundleID: nil))
        #expect(SystemApps.isIgnored(app: "Screen Journal", bundleID: "me.journal", ownBundleID: "me.journal"))
        #expect(!SystemApps.isIgnored(app: "Mail", bundleID: "com.apple.mail", ownBundleID: "me.journal"))
        #expect(!SystemApps.isIgnored(app: nil, bundleID: nil, ownBundleID: nil))
    }
}

struct DigestCodingTests {
    @Test func roundTripsDayDigest() throws {
        let note = EventRecord(at: base, kind: .note, windowTitle: "Inbox", frameID: "120000-d1", text: "hi")
        let digest = DaySummary.digest(day: "2026-10-21", sessions: SessionBuilder.sessions(from: [
            frame("a", at: 0, for: 10, app: "Mail"), frame("b", at: 10, for: 10, app: "Excel"),
        ]), events: [note])
        let line = try JournalCoding.line(digest, timeZone: rome)
        #expect(try JournalCoding.decodeLines(DayDigest.self, from: line) == [digest])
    }

    @Test func decodesDigestWrittenBeforeWindowTransitions() throws {
        let old = #"{"activeSeconds":60,"apps":[],"day":"2026-10-20","notes":[],"sessionCount":1,"transitions":[],"windows":[]}"#
        let decoded = try JournalCoding.decodeLines(DayDigest.self, from: old)
        #expect(decoded.first?.windowTransitions == [])
        #expect(decoded.first?.activeSeconds == 60)
    }
}

struct CodingTests {
    @Test func roundTripsFrameRecordAsSingleJSONLine() throws {
        let record = frame("a", at: 0, for: 10, app: "Mail", title: "Inbox")
        let line = try JournalCoding.line(record, timeZone: rome)
        #expect(!line.contains("\n"))
        #expect(line.contains("+02:00") || line.contains("+01:00"))
        let decoded = try JournalCoding.decodeLines(FrameRecord.self, from: line + "\n" + line)
        #expect(decoded == [record, record])
    }
}

struct SettledWindowTests {
    func window(_ bundleID: String, _ title: String?, x: CGFloat = 0) -> WindowInfo {
        WindowInfo(app: bundleID, bundleID: bundleID, title: title, bounds: CGRect(x: x, y: 0, width: 500, height: 500), layer: 0)
    }

    @Test func sameWindowIsSettledEvenIfItMoved() {
        #expect(WindowPlacement.settled(before: window("ghostty", "zsh"), after: window("ghostty", "zsh", x: 40)))
        #expect(WindowPlacement.settled(before: nil, after: nil))
    }

    @Test(arguments: [
        ("app switched", "chrome", "zsh"),
        ("title changed", "ghostty", "Verify"),
    ])
    func switchMidCaptureIsNotSettled(_ name: String, bundleID: String, title: String) {
        #expect(!WindowPlacement.settled(before: window("ghostty", "zsh"), after: window(bundleID, title)), "\(name)")
    }

    @Test func windowAppearingOrClosingIsNotSettled() {
        #expect(!WindowPlacement.settled(before: nil, after: window("ghostty", "zsh")))
        #expect(!WindowPlacement.settled(before: window("ghostty", "zsh"), after: nil))
    }
}
