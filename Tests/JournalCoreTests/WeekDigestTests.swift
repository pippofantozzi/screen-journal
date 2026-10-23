import Testing
@testable import JournalCore

struct WeekDigestTests {
    func day(_ name: String, _ frames: [FrameRecord], notes: [EventRecord] = []) -> DayDigest {
        DaySummary.digest(day: name, sessions: SessionBuilder.sessions(from: frames), events: notes)
    }

    var week: [DayDigest] {
        [
            day("2026-10-21", [
                frame("a", at: 0, for: 600, app: "Excel", title: "Report.xlsx"),
                frame("b", at: 600, for: 60, app: "Mail", title: "Inbox"),
            ], notes: [EventRecord(at: base, kind: .note, text: "export again")]),
            day("2026-10-19", [
                frame("c", at: 0, for: 300, app: "Excel", title: "Report.xlsx"),
                frame("d", at: 300, for: 120, app: "Mail", title: "Draft"),
            ]),
            day("2026-10-20", [
                frame("e", at: 0, for: 120, app: "Excel", title: "Report.xlsx"),
                frame("f", at: 120, for: 60, app: "Mail", title: "Inbox"),
            ]),
        ]
    }

    @Test func coversSevenDatesEndingToday() {
        let old = day("2026-10-14", [frame("z", at: 0, for: 6000, app: "Old")])
        let md = WeekDigest.markdown(week + [old], endingOn: "2026-10-21", timeZone: rome)
        #expect(md.hasPrefix("# Week of 2026-10-15 – 2026-10-21\n"))
        #expect(md.contains("Active: 21m across 3 days."))
        #expect(!md.contains("Old"))
    }

    @Test func weekCrossesMonthBoundary() {
        #expect(WeekDigest.markdown([], endingOn: "2026-11-03", timeZone: rome).hasPrefix("# Week of 2026-10-28 – 2026-11-03\n"))
    }

    @Test func findsWindowsSeenOnSeveralDaysMostDaysFirst() {
        let recurring = WeekDigest.recurringWindows(week)
        #expect(recurring.map(\.name) == ["Excel — Report.xlsx", "Mail — Inbox"])
        #expect(recurring.map(\.days) == [3, 2])
        #expect(recurring.map(\.seconds) == [1020, 120])
    }

    @Test func singleDayWindowsAreNotRecurring() {
        #expect(!WeekDigest.recurringWindows(week).map(\.name).contains("Mail — Draft"))
    }

    @Test func sumsAppTimeAndSwitchesAcrossDays() {
        let md = WeekDigest.markdown(week, endingOn: "2026-10-21", timeZone: rome)
        #expect(md.hasPrefix("# Week of 2026-10-15 – 2026-10-21\n"))
        #expect(md.contains("Active: 21m across 3 days."))
        #expect(md.contains("- 17m Excel\n- 4m Mail"))
        #expect(md.contains("- 3× Excel → Mail"))
        #expect(md.contains("## Frequent window switches\n\n- 2× Excel — Report.xlsx → Mail — Inbox\n- 1× Excel — Report.xlsx → Mail — Draft"))
        #expect(md.contains("- 3 days, 17m Excel — Report.xlsx"))
    }

    @Test func aSingleDaySaysSoAndExplainsMissingRecurringWindows() {
        let md = WeekDigest.markdown([week[0]], endingOn: "2026-10-21", timeZone: rome)
        #expect(md.contains("Active: 11m across 1 day."))
        #expect(md.contains("## Recurring windows\n\nNone yet: a window shows up here once it comes back on a second day.\n"))
    }

    @Test func groupsNotesByDay() {
        let md = WeekDigest.markdown(week, endingOn: "2026-10-21", timeZone: rome)
        #expect(md.contains("### 2026-10-21\n\n- 19:46 — export again"))
        #expect(!md.contains("### 2026-10-19"))
    }
}
