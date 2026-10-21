import Foundation
import Testing
@testable import JournalCore

struct JournalCommandTests {
    func launch(_ arguments: String...) -> Launch {
        Launch.parse(["/Applications/ScreenJournal.app/Contents/MacOS/ScreenJournal"] + arguments, timeZone: rome)
    }

    func local(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rome
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: text)!
    }

    @Test func noSubcommandStartsTheApp() {
        #expect(launch() == .app)
        #expect(launch("-psn_0_12345") == .app)
        #expect(launch("-NSDocumentRevisionsDebugMode", "YES") == .app)
    }

    @Test func forgetsALocalRangeInMinutesOrSeconds() {
        #expect(launch("forget", "--from", "2026-10-21T18:57", "--to", "2026-10-21T19:00:30")
            == .command(.forget(.range(from: local("2026-10-21T18:57:00"), to: local("2026-10-21T19:00:30")), apply: false), root: nil))
    }

    @Test func rangesMaySpanDays() {
        #expect(launch("forget", "--from", "2026-10-20T23:00", "--to", "2026-10-21T01:00", "--apply")
            == .command(.forget(.range(from: local("2026-10-20T23:00:00"), to: local("2026-10-21T01:00:00")), apply: true), root: nil))
    }

    @Test func termsRepeat() {
        #expect(launch("forget", "--term", "WhatsApp", "--term", "wnatsap", "--apply")
            == .command(.forget(.terms(["WhatsApp", "wnatsap"]), apply: true), root: nil))
    }

    @Test func tidyAndRebuildTakeARoot() {
        #expect(launch("tidy", "--keep-days", "0", "--root", "/tmp/sj") == .command(.tidy(keepDays: 0, apply: false), root: "/tmp/sj"))
        #expect(launch("--root", "/tmp/sj", "rebuild") == .command(.rebuild, root: "/tmp/sj"))
    }

    @Test(arguments: [
        ["forget"],
        ["forget", "--from", "2026-10-21T19:00"],
        ["forget", "--from", "2026-10-21T19:00", "--to", "2026-10-21T18:00"],
        ["forget", "--from", "yesterday", "--to", "2026-10-21T18:00"],
        ["forget", "--term", "  "],
        ["forget", "--term", "a", "--from", "2026-10-21T18:00", "--to", "2026-10-21T19:00"],
        ["tidy"],
        ["tidy", "--keep-days", "-1"],
        ["tidy", "--keep-days", "7", "--force"],
        ["rebuild", "--apply"],
        ["rebuild", "--root"],
    ])
    func rejectsWhatItCannotDoSafely(arguments: [String]) {
        guard case .invalid = Launch.parse(["sj"] + arguments, timeZone: rome) else {
            Issue.record("accepted \(arguments)")
            return
        }
    }
}
