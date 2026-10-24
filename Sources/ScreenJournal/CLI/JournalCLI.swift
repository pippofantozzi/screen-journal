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
        case let .label(day, titlesOnly, apply): return label(day: day, titlesOnly: titlesOnly, apply: apply)
        case let .cases(day, out, apply): return cases(day: day, out: URL(filePath: out), apply: apply)
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
                    try store.pruneLabels(day: day.day)
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
        var deletions: [DaySlim] = []
        for day in old {
            switch slim(day) {
            case .success(let slim) where !slim.images.isEmpty: deletions.append(slim)
            case .success: continue
            case .failure(let refusal): print("\(day): \(refusal.reason)")
            }
        }
        let verb = apply ? "freed" : "frees"
        for deletion in deletions {
            if apply {
                // Rows first, so no row ever points at a deleted screenshot.
                do {
                    try store.rewrite(day: deletion.day, frames: deletion.frames, events: deletion.rows.events, sessions: deletion.rows.sessions)
                } catch { return failed(error) }
                store.deleteImages(deletion.images, day: deletion.day)
            }
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

    /// One old day's tidy: screenshots to delete, and its rows repointed at the screenshots that stay.
    private struct DaySlim {
        let day: String
        let rows: JournalStore.DayRows
        let images: [String]
        let frames: [FrameRecord]
        let bytes: Int64
    }

    private struct Refusal: Error {
        let reason: String
    }

    private func slim(_ day: String) -> Result<DaySlim, Refusal> {
        guard let rows = try? store.rows(day: day) else { return .failure(Refusal(reason: "Couldn't read this day's rows.")) }
        let plan = Tidy.plan(
            frames: rows.frames, sessions: rows.sessions,
            notes: rows.events.filter { $0.kind == .note }, imagesOnDisk: store.imagesOnDisk(day: day)
        )
        switch plan {
        case let .slim(images, frames):
            return .success(DaySlim(day: day, rows: rows, images: images, frames: frames, bytes: store.size(day: day, files: images)))
        case .refused(let reason):
            return .failure(Refusal(reason: reason))
        }
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

    // MARK: label

    private typealias Ask = SessionSorter.Ask

    private func label(day: String?, titlesOnly: Bool, apply: Bool) -> Int32 {
        let setup: LabelSetup
        switch store.labelSetup() {
        case .success(let found): setup = found
        case .failure(let error): return failed(error)
        }
        let days = day.map { [$0] } ?? store.dayNames().sorted()
        guard days.allSatisfy(store.dayNames().contains) else {
            print("No captured day \(day ?? "").")
            return 1
        }
        let asks: [Ask]
        let sorter = SessionSorter(store: store), now = Date()
        do { asks = try days.flatMap { try sorter.pending($0, setup: setup, titlesOnly: titlesOnly, now: now) } } catch { return failed(error) }

        print(setup.about.isEmpty ? "No description of your work yet (Settings, or about in labels.json)." : "About your work: \(setup.about)")
        print("Task kinds: \(setup.kinds.map(\.name).joined(separator: ", ")).")
        for day in days {
            let count = asks.filter { $0.day == day }.count, looks = asks.filter { $0.day == day && $0.screenshot != nil }.count
            if count > 0 { print("\(day): \(plural(count, "session")) to label\(looks > 0 ? ", \(looks) with the screenshot" : "").") }
        }
        guard !asks.isEmpty else {
            print("Every session is labelled.\n")
            printHandoff(days, setup: setup)
            return 0
        }
        let sent = titlesOnly ? "your description, app, window titles and durations" : "your description, app, window titles, durations and up to 600 characters of screen text (keys redacted)"
        let retention = DecisionGateway.zeroRetention ? "zero data retention, no prompt training" : "no prompt training"
        print("Sends, per session: \(sent), to \(DecisionGateway.model) through the Vercel AI Gateway (\(retention)).")
        if asks.contains(where: { $0.screenshot != nil }) {
            print("Sessions with nothing redacted on screen go to \(DecisionGateway.lookModel) instead, with the screenshot (Settings → Advanced).")
        }
        guard apply else {
            print("\nDry run: nothing sent. Add --apply to label them.\n")
            printHandoff(days, setup: setup)
            return 0
        }
        guard let gateway = DecisionGateway.configured() else {
            print("\nNo AI Gateway key: save one in Settings → Advanced, or set \(DecisionGateway.keyName).")
            return 1
        }

        let outcome: SessionSorter.Outcome
        switch blocking({ await sorter.sort(asks, setup: setup, gateway: gateway) }) {
        case .success(let found): outcome = found
        case .failure(let error): return failed(error)
        }
        let failures = outcome.failures
        print("\nLabelled \(plural(outcome.sorted, "session")).")
        if let first = failures.first {
            print("\(plural(failures.count, "session")) failed (first: \(first)). Run again to retry them.")
        }
        print("")
        printHandoff(days, setup: setup)
        return failures.isEmpty ? 0 : 1
    }

    // MARK: cases

    /// Every session whose screenshot can be sent, whatever its labels say. Nothing redacted, since a key on screen would leave as pixels.
    private func lookAsks(_ day: String, setup: LabelSetup) throws -> [Ask] {
        let rows = try store.rows(day: day)
        let sessions = rows.sessions
        return sessions.indices.compactMap { i in
            let state = SessionSorter.state(at: i, of: sessions, frames: rows.frames, setup: setup, textLimit: 600)
            let image = store.screenshot(of: sessions[i])
            guard Labeling.wantsLook(state), FileManager.default.fileExists(atPath: image.path) else { return nil }
            return Ask(day: day, session: sessions[i], state: state, screenshot: image)
        }
    }

    /// One folder per session: the request as sent (the image beside it as screen.jpg), and the raw reply.
    /// Holds screenshots and screen text, so it belongs outside any repository.
    private func cases(day: String?, out: URL, apply: Bool) -> Int32 {
        let setup: LabelSetup
        switch store.labelSetup() {
        case .success(let found): setup = found
        case .failure(let error): return failed(error)
        }
        let days = day.map { [$0] } ?? store.dayNames().sorted()
        let asks: [Ask]
        do { asks = try days.flatMap { try lookAsks($0, setup: setup) } } catch { return failed(error) }
        print("\(plural(asks.count, "session")) with a screenshot and nothing redacted, to \(DecisionGateway.lookModel); nothing is labelled.")
        guard apply else {
            print("Dry run: nothing sent. Add --apply to ask and keep them in \(out.path).")
            return 0
        }
        guard let gateway = DecisionGateway.configured() else {
            print("No AI Gateway key: save one in Settings → Advanced, or set \(DecisionGateway.keyName).")
            return 1
        }
        let kinds = setup.kinds
        let results = blocking {
            await withTaskGroup(of: (Ask, Data?, Result<CaseFiles, LabelError>).self) { group in
                var results: [(Ask, Data?, Result<CaseFiles, LabelError>)] = []
                var next = asks.makeIterator()
                func start() {
                    guard let ask = next.next() else { return }
                    group.addTask {
                        guard let jpeg = ask.screenshot.flatMap({ ImageCodec.jpeg(at: $0) }),
                              let body = try? DecisionGateway.body(ask.state, kinds: kinds, screenshot: jpeg)
                        else { return (ask, nil, .failure(LabelError(message: "Couldn't read the screenshot."))) }
                        return (ask, jpeg, await gateway.reply(to: body, withImage: true).map { reply in Self.caseFiles(body: body, reply: reply) })
                    }
                }
                for _ in 0..<8 { start() }
                for await result in group {
                    results.append(result)
                    start()
                }
                return results
            }
        }
        var kept = 0, failures: [String] = []
        for (ask, jpeg, result) in results {
            switch result {
            case .success(let files):
                let folder = out.appending(path: caseName(ask))
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try files.request.write(to: folder.appending(path: "request.json"))
                    try files.reply.write(to: folder.appending(path: "reply.json"))
                    try jpeg?.write(to: folder.appending(path: "screen.jpg"))
                    kept += 1
                } catch { failures.append(error.localizedDescription) }
            case .failure(let error): failures.append(error.message)
            }
        }
        print("Kept \(plural(kept, "case")) in \(out.path).")
        if let first = failures.first { print("\(plural(failures.count, "session")) failed (first: \(first)).") }
        return failures.isEmpty ? 0 : 1
    }

    private struct CaseFiles: Sendable {
        let request: Data
        let reply: Data
    }

    /// The request without the base64 image, pretty, so a person or a replay can read it.
    private static func caseFiles(body: Data, reply: Data) -> CaseFiles {
        func pretty(_ data: Data, dropping key: String? = nil) -> Data {
            guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
            if let key { object[key] = nil }
            return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? data
        }
        return CaseFiles(request: pretty(body, dropping: "assets"), reply: pretty(reply))
    }

    private func caseName(_ ask: Ask) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = store.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return formatter.string(from: ask.session.start)
    }

    /// Time per task, then the windows agents could take most time off, across the days.
    private func printHandoff(_ days: [String], setup: LabelSetup) {
        var sessions: [Session] = [], labels: [Label] = []
        for day in days {
            guard let rows = try? store.rows(day: day), let found = try? store.labels(day: day) else { continue }
            sessions += rows.sessions
            labels += found
        }
        let tasks = Labeling.tasks(sessions: sessions, labels: labels, def: setup.def)
        guard !tasks.isEmpty else { return }
        print("Time by task (all / work / what agents could take over of the work):")
        for t in tasks {
            print("  \(Format.clock(t.seconds))\t\(Format.clock(t.work))\t\(Format.clock(t.handoff))\t\(t.task)")
        }
        let top = Labeling.candidates(sessions: sessions, labels: labels, def: setup.def).filter { $0.handoff >= 60 }.prefix(15)
        guard !top.isEmpty else { return }
        print("\nWhere to look first (windows by work time agents could take over; read their frames before believing it):")
        for c in top {
            print("  \(Format.clock(c.handoff)) of \(Format.clock(c.seconds))\t\(c.task)\t\(c.app) | \(c.window)\t\(plural(c.sessions, "session"))")
        }
    }

    /// The command line is synchronous; network work runs on the cooperative pool while it waits.
    private func blocking<T>(_ work: @escaping @Sendable () async -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: T?
        Task.detached {
            result = await work()
            done.signal()
        }
        done.wait()
        return result!
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
