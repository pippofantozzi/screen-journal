import Foundation
import Testing
@testable import JournalCore

/// A frame row with full control over what the forget/tidy plans look at.
func row(_ id: String, at offset: TimeInterval, for duration: TimeInterval = 10, display: Int = 1, focused: Bool = true,
         app: String = "Chrome", title: String? = "Tab", image: String? = nil,
         text: String? = nil, newLines: [String]? = nil) -> FrameRecord {
    FrameRecord(
        id: id, start: base + offset, end: base + offset + duration, display: display, focused: focused,
        app: app, bundleID: "id.\(app)", windowTitle: title, image: image ?? "frames/\(id).heic",
        text: text, newLines: newLines
    )
}

struct ForgetRangeTests {
    let frames = [
        row("a", at: 0, text: "one"),
        row("b", at: 10, newLines: ["two"]),
        row("c", at: 20, newLines: ["three"]),
    ]

    func plan(_ from: TimeInterval, _ to: TimeInterval, events: [EventRecord] = []) -> Forget.Plan {
        Forget.plan(frames: frames, events: events, sessions: [], target: .range(from: base + from, to: base + to))
    }

    @Test func isHalfOpen() {
        let events = [EventRecord(at: base + 10, kind: .note, text: "in"), EventRecord(at: base + 20, kind: .note, text: "out")]
        let p = plan(10, 20, events: events)
        #expect(p.frames.map(\.id) == ["a", "c"])
        #expect(p.events.map(\.text) == ["out"])
        #expect(p.deleteImages == ["frames/b.heic"])
    }

    @Test func removesPartlyOverlappingFramesAndReportsTheirFullSpan() {
        let p = plan(15, 25)
        #expect(p.frames.map(\.id) == ["a"])
        #expect(p.removedSpan == DateInterval(start: base + 10, end: base + 30))
    }

    @Test func removesOverlappingSessions() {
        let sessions = SessionBuilder.sessions(from: [frame("x", at: 0, for: 10, app: "Mail"), frame("y", at: 10, for: 10, app: "Excel")])
        let p = Forget.plan(frames: [], events: [], sessions: sessions, target: .range(from: base + 10, to: base + 15))
        #expect(p.sessions.map(\.app) == ["Mail"])
        #expect(p.removedSpan == nil)
    }

    @Test func deletesRemovedImageStillUsedByKeptRowAndCountsIt() {
        let frames = [row("a", at: 0, text: "one"), row("b", at: 10, image: "frames/a.heic", newLines: ["two"])]
        let p = Forget.plan(frames: frames, events: [], sessions: [], target: .range(from: base, to: base + 10))
        #expect(p.frames.map(\.id) == ["b"])
        #expect(p.deleteImages == ["frames/a.heic"])
        #expect(p.brokenReferences == 1)
    }
}

struct ForgetTermsTests {
    func plan(_ frames: [FrameRecord], _ terms: [String], events: [EventRecord] = [], sessions: [Session] = []) -> Forget.Plan {
        Forget.plan(frames: frames, events: events, sessions: sessions, target: .terms(terms))
    }

    @Test func removesTheWholeVisitButNotTheNextWindow() {
        let frames = [
            row("a", at: 0, text: "Invoice 42\nTotal"),
            row("b", at: 10, image: "frames/a.heic", newLines: ["Paid"]),
            row("c", at: 20, image: "frames/a.heic"),
            row("d", at: 30, title: "Other", text: "Nothing here"),
        ]
        let p = plan(frames, ["invoice"])
        #expect(p.frames.map(\.id) == ["d"])
        #expect(p.deleteImages == ["frames/a.heic"])
        #expect(p.brokenReferences == 0)
        #expect(p.removedSpan == DateInterval(start: base, end: base + 30))
    }

    @Test func aMatchLaterInTheVisitRemovesItsStartToo() {
        let frames = [row("a", at: 0, text: "Hello"), row("b", at: 10, newLines: ["Invoice 42"])]
        #expect(plan(frames, ["INVOICE"]).frames.isEmpty)
    }

    @Test func newTextInTheSameWindowStartsANewVisit() {
        let frames = [row("a", at: 0, text: "Hello"), row("b", at: 10, text: "Invoice 42")]
        #expect(plan(frames, ["invoice"]).frames.map(\.id) == ["a"])
    }

    @Test func visitsArePerDisplay() {
        let frames = [
            row("a", at: 0, display: 1, text: "Hello"),
            row("b", at: 0, display: 2, text: "Other"),
            row("c", at: 10, display: 1, newLines: ["Invoice"]),
        ]
        #expect(plan(frames, ["invoice"]).frames.map(\.id) == ["b"])
    }

    @Test func matchesIgnoringCaseAndDiacritics() {
        let frames = [row("a", at: 0, title: "Verificação de conta", text: "x"), row("b", at: 10, title: "Other", text: "y")]
        #expect(plan(frames, ["verificacao"]).frames.map(\.id) == ["b"])
    }

    @Test func matchesAppName() {
        let frames = [row("a", at: 0, app: "WhatsApp", text: "x"), row("b", at: 10, app: "Mail", text: "y")]
        #expect(plan(frames, ["whatsapp"]).frames.map(\.app) == ["Mail"])
    }

    @Test func removesMatchingEvents() {
        let events = [
            EventRecord(at: base, kind: .appSwitch, app: "WhatsApp"),
            EventRecord(at: base, kind: .note, windowTitle: "Bank — Login", text: "ugh"),
            EventRecord(at: base, kind: .note, text: "keep me"),
        ]
        let p = plan([], ["whatsapp", "bank"], events: events)
        #expect(p.events.map(\.text) == ["keep me"])
    }

    @Test func removesSessionsOfRemovedVisitsOnly() {
        let frames = [
            row("a", at: 0, app: "Mail", title: "Inbox", text: "Invoice"),
            row("b", at: 10, app: "Excel", title: "Budget", text: "numbers"),
            row("c", at: 20, display: 2, focused: false, app: "Slack", title: "general", text: "invoice too"),
        ]
        let sessions = SessionBuilder.sessions(from: frames)
        let p = plan(frames, ["invoice"], sessions: sessions)
        #expect(p.frames.map(\.id) == ["b"])
        #expect(p.sessions.map(\.app) == ["Excel"])
    }

    @Test func deletesImagesOnlyRemovedSessionsReferenced() {
        let frames = [row("a", at: 0, text: "Invoice")]
        let orphan = Session(start: base, end: base + 10, app: "Chrome", bundleID: "id.Chrome", windowTitle: "Tab",
                             frames: 1, representativeFrame: "frames/old.heic")
        let p = plan(frames, ["invoice"], sessions: [orphan])
        #expect(p.sessions.isEmpty)
        #expect(p.deleteImages == ["frames/a.heic", "frames/old.heic"])
    }
}

struct TidyTests {
    let frames = [
        row("a", at: 0, text: "start"),
        row("b", at: 10, newLines: ["more"]),
        row("c", at: 20, newLines: ["even more"]),
        row("x", at: 30, newLines: ["filler"]),
        row("d", at: 40, title: "Other", text: "next window"),
    ]

    var sessions: [Session] {
        [Session(start: base, end: base + 50, app: "Chrome", bundleID: "id.Chrome", windowTitle: "Tab",
                 frames: 5, representativeFrame: "frames/c.heic")]
    }

    let note = EventRecord(at: base + 15, kind: .note, frameID: "b", text: "look")

    @Test func keepsVisitStartsRepresentativesAndNotedFrames() {
        let onDisk = ["frames/a.heic", "frames/b.heic", "frames/c.heic", "frames/x.heic", "frames/d.heic", "frames/stray.heic"]
        let plan = Tidy.plan(frames: frames, sessions: sessions, notes: [note], imagesOnDisk: onDisk)
        #expect(plan == .delete(["frames/stray.heic", "frames/x.heic"]))
    }

    @Test func ignoresImagesNotOnDisk() {
        let plan = Tidy.plan(frames: frames, sessions: sessions, notes: [note], imagesOnDisk: ["frames/x.heic"])
        #expect(plan == .delete(["frames/x.heic"]))
    }

    @Test func refusesWithoutSessions() {
        let plan = Tidy.plan(frames: frames, sessions: [], notes: [], imagesOnDisk: ["frames/x.heic"])
        guard case .refused = plan else { Issue.record("expected refusal, got \(plan)"); return }
    }

    @Test func refusesWithoutFrames() {
        let plan = Tidy.plan(frames: [], sessions: sessions, notes: [], imagesOnDisk: ["frames/x.heic"])
        guard case .refused = plan else { Issue.record("expected refusal, got \(plan)"); return }
    }

    @Test func nothingOnDiskIsNothingToDo() {
        #expect(Tidy.plan(frames: [], sessions: [], notes: [], imagesOnDisk: []) == .delete([]))
    }
}
