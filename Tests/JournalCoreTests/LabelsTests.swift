import Foundation
import Testing
@testable import JournalCore

/// Assembled so the source holds no key-shaped literal for secret scanners to flag.
private let fakeStripeKey = "sk_" + "live_abcdefghijklmnopqrstuvwxyz"

private let setup = LabelSetup(about: "I do marketing for clients.", tasks: ["Reels"])

private func session(at offset: TimeInterval, for duration: TimeInterval = 60, app: String = "Chrome", title: String = "Tab") -> Session {
    Session(start: base + offset, end: base + offset + duration, app: app, bundleID: "id.\(app)",
            windowTitle: title, frames: 1, representativeFrame: "frames/x.heic")
}

private func label(_ s: Session, work: Double = 1, automatable: Double = 0.5, task: String = "admin",
                   def: String = setup.def, source: Label.Source = .model) -> Label {
    Label(session: s.start, work: work, automatable: automatable, task: task, def: def, source: source)
}

struct LabelSetupTests {
    @Test func herTasksFollowTheDefaultsOnceEach() {
        let kinds = LabelSetup(tasks: ["Reels", " reels ", "design", ""]).kinds
        #expect(kinds.map(\.name) == TaskKind.defaults.map(\.name) + ["reels"])
        #expect(kinds.last == TaskKind(name: "reels", description: "reels"))
    }

    @Test func addingAKindTrimsItAndSkipsBlanksAndRepeats() {
        #expect(LabelSetup.adding("  Newsletters ", to: ["Reels"]) == ["Reels", "Newsletters"])
        #expect(LabelSetup.adding("reels", to: ["Reels"]) == ["Reels"])
        #expect(LabelSetup.adding("  ", to: ["Reels"]) == ["Reels"])
        #expect(LabelSetup.adding(" Design", to: ["Reels"]) == ["Reels"])
    }

    @Test func aKindAlreadyIncludedNamesTheChipItMatches() {
        #expect(LabelSetup.included(" Design ", in: ["Reels"]) == "design")
        #expect(LabelSetup.included("REELS", in: ["Reels"]) == "Reels")
        #expect(LabelSetup.included("Newsletters", in: ["Reels"]) == nil)
    }

    @Test func editingWhatTheModelIsToldChangesTheDef() {
        #expect(setup.def == LabelSetup(about: setup.about, tasks: ["reels"]).def)
        #expect(setup.def != LabelSetup(about: "I code.", tasks: setup.tasks).def)
        #expect(setup.def != LabelSetup(about: setup.about, tasks: ["Reels", "Newsletters"]).def)
        #expect(setup.def.count == 8)
    }

    @Test func screenshotsAreOnUnlessTurnedOffAndAskNothingNew() {
        #expect(LabelSetup().screenshots)
        #expect(LabelSetup.parse(#"{"about": "", "tasks": []}"#) == .success(LabelSetup()))
        // The old setting only covered windows with little text, and was saved off by default: it doesn't carry over.
        #expect(LabelSetup.parse(#"{"about": "", "tasks": [], "look": false}"#) == .success(LabelSetup()))
        #expect(LabelSetup.parse(#"{"about": "", "tasks": [], "screenshots": false}"#) == .success(LabelSetup(screenshots: false)))
        #expect(LabelSetup(about: setup.about, tasks: setup.tasks, screenshots: false).def == setup.def)
    }

    @Test func roundTripsThroughTheFile() throws {
        #expect(LabelSetup.parse(try setup.file()) == .success(setup))
        let textOnly = LabelSetup(about: setup.about, tasks: setup.tasks, screenshots: false)
        #expect(LabelSetup.parse(try textOnly.file()) == .success(textOnly))
        guard case .failure(let error) = LabelSetup.parse("not json") else { Issue.record("accepted"); return }
        #expect(error.message.contains("labels.json"))
    }
}

struct PendingTests {
    let a = session(at: 0), b = session(at: 100)

    @Test func asksSessionsUnansweredUnderTheCurrentSetup() {
        let labels = [label(a), label(b, def: "stale000")]
        #expect(Labeling.pending(sessions: [a, b], labels: labels, def: setup.def) == [b])
    }

    @Test func aCorrectionCountsAsAnswered() {
        #expect(Labeling.pending(sessions: [a], labels: [label(a, source: .agent)], def: setup.def).isEmpty)
    }
}

struct CurrentLabelTests {
    let a = session(at: 0)

    @Test func latestAnswerWinsAndCorrectionsWinOverTheModel() {
        let corrected = [label(a, work: 0, source: .agent), label(a, work: 0.9)]
        #expect(Labeling.current(corrected, def: setup.def)[a.start]?.work == 0)
        let asked = [label(a, task: "admin"), label(a, task: "design")]
        #expect(Labeling.current(asked, def: setup.def)[a.start]?.task == "design")
    }

    @Test func anAnswerThatSawTheScreenshotBeatsTextOnlyButNotACorrection() {
        #expect(Labeling.current([label(a, task: "design", source: .look), label(a, task: "admin")], def: setup.def)[a.start]?.task == "design")
        #expect(Labeling.current([label(a, task: "admin", source: .agent), label(a, task: "design", source: .look)], def: setup.def)[a.start]?.task == "admin")
    }

    @Test func dropsAnswersFromAnotherSetup() {
        #expect(Labeling.current([label(a, def: "stale000")], def: setup.def).isEmpty)
    }

    @Test func forgottenSessionsLoseTheirAnswers() {
        let removed = session(at: 500)
        #expect(Labeling.kept([label(a), label(removed)], sessions: [a]) == [label(a)])
    }
}

struct LookTests {
    let a = session(at: 0), b = session(at: 100), c = session(at: 200), d = session(at: 300)

    @Test func looksUnlessSomethingWasRedacted() {
        #expect(Labeling.wantsLook(SessionState(a, frames: [row("x", at: 0, text: "Canva")])))
        #expect(Labeling.wantsLook(SessionState(a, frames: [row("x", at: 0, text: String(repeating: "word ", count: 30))])))
        #expect(!Labeling.wantsLook(SessionState(a, frames: [row("x", at: 0, text: fakeStripeKey)])))
    }

    @Test func aSessionThatMayStillBeGoingWaits() {
        let now = base + 1000
        let sessions = [session(at: 0, for: 600), session(at: 600, for: 300), session(at: 900, for: 90)]
        #expect(Labeling.finished(sessions, at: now) == [sessions[0]])
    }

    @Test func neverLooksWhenAKeyWasHiddenAnywhereOnScreen() {
        // Its own text is clean, but a terminal behind it showed a key: the pixels would carry it.
        #expect(!Labeling.wantsLook(SessionState(a, frames: [row("x", at: 0, text: "Canva", secretOnScreen: true)])))
        // Past the text limit, or with no text sent at all, it still counts.
        #expect(SessionState(a, frames: [row("x", at: 0, text: "Canva\n" + fakeStripeKey)], textLimit: 0).secretOnScreen)
    }

    @Test func sessionsNotYetSeenAreUnlabelledOrTextOnly() {
        let labels = [label(b), label(c, source: .look), label(d, source: .agent)]
        #expect(Labeling.unseen(sessions: [a, b, c, d], labels: labels, def: setup.def) == [a, b])
    }
}

struct HandoffTests {
    let sheet = session(at: 0, for: 600, app: "Sheets", title: "Invoices")
    let sheetAgain = session(at: 700, for: 300, app: "Sheets", title: "Invoices")
    let feed = session(at: 1000, for: 1200, app: "Chrome", title: "Instagram")
    let call = session(at: 2200, for: 600, app: "Zoom", title: "Call")

    var labels: [Label] {
        [label(sheet, work: 1, automatable: 0.8, task: "admin"), label(sheetAgain, work: 1, automatable: 0.6, task: "content"),
         label(feed, work: 0.25, automatable: 0.5, task: "leisure"), label(call, work: 1, automatable: 0, task: "meeting")]
    }

    @Test func timePerTaskWithTheShareAgentsCouldTakeOverOfWork() {
        let tasks = Labeling.tasks(sessions: [sheet, sheetAgain, feed, call], labels: labels, def: setup.def)
        #expect(tasks == [
            .init(task: "leisure", seconds: 1200, work: 300, handoff: 150),
            .init(task: "admin", seconds: 600, work: 600, handoff: 480),
            .init(task: "meeting", seconds: 600, work: 600, handoff: 0),
            .init(task: "content", seconds: 300, work: 300, handoff: 180),
        ])
    }

    @Test func windowsRankByTimeAgentsCouldTakeOver() {
        let candidates = Labeling.candidates(sessions: [sheet, sheetAgain, feed, call], labels: labels, def: setup.def)
        #expect(candidates.map(\.window) == ["Invoices", "Instagram", "Call"])
        #expect(candidates.first == .init(app: "Sheets", window: "Invoices", task: "admin", seconds: 900, handoff: 660, sessions: 2))
    }

    @Test func unlabelledSessionsAreLeftOut() {
        #expect(Labeling.candidates(sessions: [sheet, call], labels: [], def: setup.def).isEmpty)
    }
}

struct WeekReportTests {
    let sheet = session(at: 0, for: 600, app: "Sheets", title: "Invoices")
    let chat = session(at: 600, for: 30, app: "Slack", title: "Client")
    let unsorted = session(at: 700, for: 300, app: "Chrome", title: "Tab")

    @Test func theSevenDaysEndingOnADay() {
        #expect(WeekReport.days(endingOn: "2026-10-23") == ["2026-10-17", "2026-10-18", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"])
    }

    @Test func tracksAllTimeAndCountsWhatIsNotSortedYet() {
        let report = WeekReport(endingOn: "2026-10-23", sessions: [sheet, chat, unsorted],
                                labels: [label(sheet, automatable: 0.8, task: "admin"), label(chat, automatable: 1, task: "communication")], def: setup.def)
        #expect(report.first == "2026-10-17" && report.last == "2026-10-23")
        #expect(report.tracked == 930 && report.unsorted == 300)
        #expect(report.tasks.map(\.task) == ["admin", "communication"])
    }

    @Test func suggestsOnlyWindowsWorthAMinuteOfHandoffAtMostThree() {
        let windows = (0..<5).map { session(at: Double($0) * 1000, for: 600, app: "App\($0)", title: "W") }
        let report = WeekReport(endingOn: "2026-10-23", sessions: windows + [chat],
                                labels: windows.map { label($0) } + [label(chat, automatable: 1)], def: setup.def)
        #expect(report.candidates.count == 3 && !report.candidates.contains { $0.app == "Slack" })
    }

    @Test func theShareClaudeCouldHelpWithIsOfAllTheTasksTime() {
        #expect(Labeling.TaskTime(task: "admin", seconds: 600, work: 600, handoff: 240).helpShare == 0.4)
        #expect(Labeling.TaskTime(task: "leisure", seconds: 0, work: 0, handoff: 0).helpShare == 0)
    }
}

struct WeekScreensTests {
    let invoice = session(at: 0, for: 600, app: "Sheets", title: "Invoices")
    let reel = session(at: 600, for: 300, app: "CapCut", title: "Reel")
    let feed = session(at: 900, for: 120, app: "Instagram", title: "Feed")
    let unsorted = session(at: 1200, for: 60)

    var report: WeekReport {
        WeekReport(endingOn: "2026-10-23", sessions: [invoice, reel, feed, unsorted], labels: [
            label(invoice, automatable: 0.8, task: "admin"),
            label(reel, automatable: 0.2, task: "content"),
            label(feed, work: 0.25, automatable: 1, task: "leisure"),
        ], def: setup.def)
    }

    @Test func showsSortedSessionsNewestFirst() {
        #expect(report.screens(task: nil, share: .any).map(\.session) == [feed, reel, invoice])
    }

    @Test func narrowsToOneTask() {
        #expect(report.screens(task: "content", share: .any).map(\.session) == [reel])
    }

    @Test func splitsByWhetherClaudeCouldProbablyTakeItOver() {
        #expect(report.screens(task: nil, share: .likely).map(\.session) == [invoice])
        #expect(report.screens(task: nil, share: .rest).map(\.session) == [feed, reel])
    }

    @Test func theShareCountsWorkOnlyLikeTheBars() {
        #expect(report.screens(task: "leisure", share: .any).first?.helpShare == 0.25)
    }

    @Test func halfIsEnoughToCountAsLikely() {
        #expect(WeekReport.Screen(session: invoice, label: label(invoice, automatable: 0.5)).isLikely)
    }
}

struct SessionStateTests {
    @Test func gathersTheSessionsOwnScreenTextRedacted() {
        let s = session(at: 0, for: 30)
        let frames = [
            row("before", at: -10, text: "earlier"),
            row("a", at: 0, text: "Inbox\nkey \(fakeStripeKey)\nok"),
            row("b", at: 10, newLines: ["Reply sent"]),
            row("other", at: 15, display: 2, focused: false, text: "second screen"),
            row("after", at: 30, newLines: ["later"]),
        ]
        let state = SessionState(s, frames: frames)
        #expect(state.app == "Chrome" && state.window == "Tab" && state.seconds == 30)
        #expect(state.screenText == "Inbox\nkey [redacted]\nok\nReply sent")
    }

    @Test func glancesAtTheSessionsEitherSide() {
        let state = SessionState(session(at: 0), before: session(at: -40, for: 40, app: "Sheets", title: "Invoices"), frames: [])
        #expect(state.before == "Sheets — Invoices (40s)")
        #expect(state.after == "nothing")
    }

    @Test func capsTheText() {
        let frames = [row("a", at: 0, text: String(repeating: "word ", count: 500))]
        #expect(SessionState(session(at: 0), frames: frames, textLimit: 50).screenText.count == 50)
    }

    @Test func titlesOnlyLeavesTheTextOut() throws {
        let state = SessionState(session(at: 0), frames: [row("a", at: 0, text: "secret")], textLimit: 0)
        let json = String(decoding: try SystemOne.request(model: "m", state: state, kinds: setup.kinds, zeroRetention: false), as: UTF8.self)
        #expect(!json.contains("secret") && !json.contains("screen_text"))
    }
}

struct SystemOneTests {
    func body(zeroRetention: Bool = false) throws -> [String: Any] {
        let state = SessionState(session(at: 0), about: setup.about, frames: [])
        let data = try SystemOne.request(model: "baseten/mammoth-1", state: state, kinds: setup.kinds, zeroRetention: zeroRetention)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test func asksWorkAutomatableAndTaskWithHerContext() throws {
        let body = try body()
        #expect(body["model"] as? String == "baseten/mammoth-1")
        #expect((body["state"] as? [String: Any])?["about_the_person"] as? String == setup.about)
        let questions = body["questions"] as? [String: [String: Any]]
        #expect(questions?["work"]?["type"] as? String == "noul")
        #expect((questions?["automatable"]?["criteria"] as? [String])?.count == 4)
        #expect((questions?["task"]?["criteria"] as? [String: String])?["reels"] == "reels")
    }

    @Test func neverAllowsTrainingAndAsksForZeroRetentionWhenOn() throws {
        #expect((try body()["providerOptions"] as? [String: [String: Bool]]) == ["gateway": ["disallowPromptTraining": true]])
        #expect((try body(zeroRetention: true)["providerOptions"] as? [String: [String: Bool]])
            == ["gateway": ["disallowPromptTraining": true, "zeroDataRetention": true]])
    }

    @Test func carriesTheScreenshotAsAnAssetTheStatePointsAt() throws {
        let state = SessionState(session(at: 0), frames: [])
        let data = try SystemOne.request(model: "m", state: state, kinds: setup.kinds, zeroRetention: false, screenshot: Data([1, 2, 3]))
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        #expect((body["state"] as? [String: Any])?["screenshot"] as? String == "<<screen>>")
        #expect((body["assets"] as? [String: [String: String]]) == ["screen": ["type": "image", "data_base64": "AQID", "format": "jpeg"]])
        let plain = try JSONSerialization.jsonObject(with: try SystemOne.request(model: "m", state: state, kinds: setup.kinds, zeroRetention: false)) as? [String: Any] ?? [:]
        #expect(plain["assets"] == nil && (plain["state"] as? [String: Any])?["screenshot"] == nil)
    }

    @Test func readsTheAnswersWithTheScoreAsAShare() {
        let data = Data(#"{"answers": {"work": {"noul": 0.9}, "automatable": {"score": 1.5}, "task": {"choice": "design"}}}"#.utf8)
        #expect(SystemOne.answers(data) == .success(.init(work: 0.9, automatable: 0.5, task: "design")))
    }

    @Test func aMissingAnswerIsAFailure() {
        let data = Data(#"{"answers": {"work": {"noul": 0.9}}}"#.utf8)
        guard case .failure(let error) = SystemOne.answers(data) else { Issue.record("accepted"); return }
        #expect(error.message.contains("Missing"))
    }
}
