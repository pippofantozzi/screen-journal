import Foundation
import JournalCore

/// `forget`, `tidy` and `rebuild` from the command line. Every change is a dry run unless `--apply` is given.
/// Writes go through JournalStore; with `--root` the running app is never quit or reopened.
struct JournalCLI {
    let command: JournalCommand
    let store: JournalStore
    private let ownsRealJournal: Bool

    init(command: JournalCommand, root: String?) {
        self.command = command
        self.store = root.map { JournalStore(root: URL(filePath: $0)) } ?? .default
        self.ownsRealJournal = root == nil
    }

    func run() -> Int32 {
        guard FileManager.default.fileExists(atPath: store.daysDir.path) else {
            print("No journal at \(store.root.path).")
            return 1
        }
        switch command {
        case let .forget(target, apply): return forget(target, apply: apply)
        case let .tidy(keepDays, apply): return tidy(keepDays: keepDays, apply: apply)
        case .rebuild: return withAppQuit { rebuild() }
        }
    }

    // MARK: forget

    /// One day's share of a forget.
    private struct DayForget {
        let day: String
        let plan: Forget.Plan
        let removedFrames: [FrameRecord]
        let removedEvents: Int
        /// Active time as summary.md counts it, before and after.
        let active: (before: TimeInterval, after: TimeInterval)
        let screenshots: [String]
        /// Size of the screenshots it deletes, measured before deleting; dry run and apply both report this.
        let bytes: Int64

        var changes: Bool { !removedFrames.isEmpty || removedEvents > 0 || !screenshots.isEmpty }
    }

    private func forget(_ target: Forget.Target, apply: Bool) -> Int32 {
        let days: [DayForget]
        do { days = try forgetDays(target).filter(\.changes) } catch { return failed(error) }
        guard !days.isEmpty else {
            print("Nothing matches; the journal is unchanged.")
            return 0
        }
        days.forEach { print(sentence($0, target: target)) }
        print(total(days))
        if case .terms = target { printVisits(days) }
        guard apply else {
            print("\nDry run: nothing changed. Add --apply to remove it.")
            return 0
        }
        return withAppQuit {
            do {
                for day in days {
                    try store.rewrite(day: day.day, frames: day.plan.frames, events: day.plan.events, sessions: day.plan.sessions)
                    store.deleteImages(day.plan.deleteImages, day: day.day)
                    try store.summarize(day: day.day)
                }
            } catch { return failed(error) }
            print("\nRemoved \(counts(days)). Freed \(megabytes(days.reduce(0) { $0 + $1.bytes })).")
            guard case .terms(let terms) = target else { return 0 }
            return confirmGone(terms)
        }
    }

    private func forgetDays(_ target: Forget.Target) throws -> [DayForget] {
        try candidateDays(target).map { day in
            let rows = try store.rows(day: day)
            let onDisk = store.imagesOnDisk(day: day)
            let plan = Forget.plan(
                frames: rows.frames, events: rows.events, sessions: rows.sessions, imagesOnDisk: onDisk, target: target
            )
            let keptIDs = Set(plan.frames.map(\.id))
            let screenshots = Set(onDisk).intersection(plan.deleteImages).sorted()
            return DayForget(
                day: day, plan: plan,
                removedFrames: rows.frames.filter { !keptIDs.contains($0.id) },
                removedEvents: rows.events.count - plan.events.count,
                active: (activeSeconds(rows.frames), activeSeconds(plan.frames)),
                screenshots: screenshots,
                bytes: store.size(day: day, files: screenshots)
            )
        }
    }

    /// A range touches its own days plus the day before, whose last moment may run past midnight.
    private func candidateDays(_ target: Forget.Target) -> [String] {
        let days = store.dayNames().sorted()
        guard case let .range(from, to) = target else { return days }
        let first = store.day(of: from.addingTimeInterval(-86400)), last = store.day(of: to)
        return days.filter { $0 >= first && $0 <= last }
    }

    private func sentence(_ day: DayForget, target: Forget.Target) -> String {
        let active = "\(Format.clock(day.active.before)) active → \(Format.clock(day.active.after))"
        var text = "\(day.day): \(active). Removes \(counts([day])) (\(megabytes(day.bytes)))."
        if case let .range(from, to) = target, let span = day.plan.removedSpan, span.start < from || span.end > to {
            text += " Because some moments overlap the range, this also covers \(clock(span.start))–\(clock(span.end))."
        }
        if day.plan.brokenReferences > 0 {
            text += " \(plural(day.plan.brokenReferences, "kept moment")) shared a removed screenshot and will show none."
        }
        return text
    }

    private func activeSeconds(_ frames: [FrameRecord]) -> TimeInterval {
        DaySummary.digest(day: "", sessions: SessionBuilder.sessions(from: frames), events: []).activeSeconds
    }

    private func total(_ days: [DayForget]) -> String {
        let bytes = days.reduce(0) { $0 + $1.bytes }
        return "Total: \(counts(days)) on \(plural(days.count, "day")), freeing \(megabytes(bytes))."
    }

    private func counts(_ days: [DayForget]) -> String {
        let frames = days.reduce(0) { $0 + $1.removedFrames.count }
        let events = days.reduce(0) { $0 + $1.removedEvents }
        let screenshots = days.reduce(0) { $0 + $1.screenshots.count }
        return "\(plural(frames, "moment")), \(plural(events, "event")), \(plural(screenshots, "screenshot"))"
    }

    private func printVisits(_ days: [DayForget]) {
        let frames = days.flatMap(\.removedFrames)
        let visits = days.reduce(0) { $0 + Visits.indices($1.removedFrames).count }
        print("\(plural(frames.count, "moment")) in \(plural(visits, "window visit")).")
        let titles = Dictionary(grouping: frames) { [$0.app, WindowTitle.stable($0.windowTitle)].compactMap { $0 }.joined(separator: " — ") }
            .map { (title: $0.key.isEmpty ? "(no window)" : $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.title) > ($1.count, $0.title) }
        guard !titles.isEmpty else { return }
        print("Windows:")
        titles.prefix(10).forEach { print("  \($0.count)× \($0.title)") }
        if titles.count > 10 { print("  …and \(plural(titles.count - 10, "more window"))") }
    }

    /// After a term forget nothing derived may still mention it.
    private func confirmGone(_ terms: [String]) -> Int32 {
        let left = store.mentions(of: terms)
        guard !left.isEmpty else {
            print("Checked: no file mentions \(terms.joined(separator: " or ")) any more.")
            return 0
        }
        print("Still mentioned in \(plural(left.count, "line")):")
        left.prefix(20).forEach { print("  " + String($0.prefix(200))) }
        return 1
    }

    // MARK: tidy

    private func tidy(keepDays: Int, apply: Bool) -> Int32 {
        let days = store.dayNames().sorted(by: >)
        let today = store.day(of: Date())
        guard let first = days.last else {
            print("The journal is empty.")
            return 0
        }
        printSizes(days)

        // Strictly before (today − keepDays) in local calendar days, so today is never touched.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.timeZone
        let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: Date()).map(store.day(of:)) ?? today
        let old = days.filter { $0 < min(cutoff, today) }
        guard !old.isEmpty else {
            let age = keepDays == 0 ? "before today" : "older than \(plural(keepDays, "day"))"
            print("Nothing \(age) yet; the journal starts \(first).")
            return 0
        }
        var deletions: [(day: String, images: [String], bytes: Int64)] = []
        for day in old {
            switch tidyPlan(day) {
            case .delete(let images) where !images.isEmpty: deletions.append((day, images, store.size(day: day, files: images)))
            case .delete: continue
            case .refused(let reason): print("\(day): \(reason)")
            }
        }
        let verb = apply ? "freed" : "frees"
        for deletion in deletions {
            if apply { store.deleteImages(deletion.images, day: deletion.day) }
            print("\(deletion.day): \(verb) \(megabytes(deletion.bytes)) (\(plural(deletion.images.count, "screenshot"))).")
        }
        let bytes = megabytes(deletions.reduce(0) { $0 + $1.bytes })
        let screenshots = plural(deletions.reduce(0) { $0 + $1.images.count }, "screenshot")
        let total = "Total: \(verb) \(bytes) on \(plural(deletions.count, "day")) (\(screenshots))."
        guard apply else {
            print(total + " Add --apply to delete them.")
            return 0
        }
        print(total + " Now:\n")
        printSizes(days)
        return 0
    }

    /// Bytes per day, newest first, with a total.
    private func printSizes(_ days: [String]) {
        let sizes = days.map { store.size(day: $0) }
        zip(days, sizes).forEach { print("\($0)  \(megabytes($1))") }
        print("Total  \(megabytes(sizes.reduce(0, +)))\n")
    }

    private func tidyPlan(_ day: String) -> Tidy.Plan {
        guard let rows = try? store.rows(day: day) else { return .refused("Couldn't read this day's rows.") }
        return Tidy.plan(
            frames: rows.frames, sessions: rows.sessions,
            notes: rows.events.filter { $0.kind == .note }, imagesOnDisk: store.imagesOnDisk(day: day)
        )
    }

    // MARK: rebuild

    private func rebuild() -> Int32 {
        let days = store.dayNames().sorted()
        do {
            for day in days { try store.summarize(day: day) }
        } catch { return failed(error) }
        print("Rebuilt \(plural(days.count, "day")), index.md and week.md.")
        return 0
    }

    // MARK: shared

    /// The app appends to today's files, so it's quit while they're rewritten and reopened after.
    private func withAppQuit(_ body: () -> Int32) -> Int32 {
        guard ownsRealJournal else { return body() }
        let app = RunningApp.quit()
        if app != nil { print("Quit Screen Journal while the journal changes.") }
        defer {
            if let app {
                RunningApp.reopen(app)
                print("Reopened Screen Journal.")
            }
        }
        return body()
    }

    private func failed(_ error: Error) -> Int32 {
        FileHandle.standardError.write(Data("Failed: \(error.localizedDescription)\n".utf8))
        return 1
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = store.timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
