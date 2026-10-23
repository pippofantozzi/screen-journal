import CoreGraphics
import Foundation
import JournalCore

/// The journal folder on disk. Every file write in the app goes through here.
struct JournalStore {
    /// One day's source rows, plus its derived sessions.
    struct DayRows {
        let frames: [FrameRecord]
        let events: [EventRecord]
        let sessions: [Session]
    }

    let root: URL
    var timeZone: TimeZone { .current }

    static let `default` = JournalStore(root: FileManager.default.homeDirectoryForCurrentUser.appending(path: "ScreenJournal"))

    var daysDir: URL { root.appending(path: "days") }
    func dayDir(_ day: String) -> URL { daysDir.appending(path: day) }
    func day(of date: Date) -> String { DayStamp(date, in: timeZone).string }

    func append(_ frame: FrameRecord) throws {
        try appendLine(try JournalCoding.line(frame, timeZone: timeZone), to: dayDir(day(of: frame.start)).appending(path: "frames.jsonl"))
    }

    func append(_ event: EventRecord) throws {
        try appendLine(try JournalCoding.line(event, timeZone: timeZone), to: dayDir(day(of: event.at)).appending(path: "events.jsonl"))
    }

    /// Returns the path relative to the day folder.
    func writeImage(_ image: CGImage, id: String, at date: Date) throws -> String {
        let relative = "frames/\(id).heic"
        let url = dayDir(day(of: date)).appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ImageCodec.writeHEIC(image, to: url)
        return relative
    }

    /// Writes CLAUDE.md and the skill unless an up-to-date copy is already there,
    /// and points `.claude/sj` at this binary so the guide's commands always run the copy that is recording.
    func installGuide() throws {
        try linkCommand()
        for file in JournalGuide.files {
            let url = root.appending(path: file.path)
            if let existing = try? String(contentsOf: url, encoding: .utf8), !JournalGuide.shouldReplace(existing) { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func linkCommand() throws {
        guard let binary = Bundle.main.executablePath else { return }
        let link = root.appending(path: JournalGuide.commandPath)
        let fm = FileManager.default
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == binary { return }
        try? fm.removeItem(at: link)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: binary)
    }

    func rows(day: String) throws -> DayRows {
        let dir = dayDir(day)
        return DayRows(
            frames: try JournalCoding.decodeLines(FrameRecord.self, from: read(dir.appending(path: "frames.jsonl"))),
            events: try JournalCoding.decodeLines(EventRecord.self, from: read(dir.appending(path: "events.jsonl"))),
            sessions: try JournalCoding.decodeLines(Session.self, from: read(dir.appending(path: "sessions.jsonl")))
        )
    }

    var labelSetupURL: URL { root.appending(path: "labels.json") }

    /// What she wrote in Settings, or nothing yet.
    func labelSetup() -> Result<LabelSetup, LabelError> {
        guard let text = try? String(contentsOf: labelSetupURL, encoding: .utf8) else { return .success(LabelSetup()) }
        return LabelSetup.parse(text)
    }

    func save(_ setup: LabelSetup) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try setup.file().write(to: labelSetupURL, atomically: true, encoding: .utf8)
    }

    /// Only the derived sessions, without reading a day's frames.
    func sessions(day: String) throws -> [Session] {
        try JournalCoding.decodeLines(Session.self, from: read(dayDir(day).appending(path: "sessions.jsonl")))
    }

    /// The seven days ending on `day` under her current setup; days with nothing on disk count as empty.
    func weekReport(endingOn day: String) -> Result<WeekReport, LabelError> {
        labelSetup().flatMap { setup in
            do {
                let days = WeekReport.days(endingOn: day)
                let sessions = try days.flatMap { try self.sessions(day: $0) }
                let labels = try days.flatMap { try self.labels(day: $0) }
                return .success(WeekReport(endingOn: day, sessions: sessions, labels: labels, def: setup.def))
            } catch {
                return .failure(LabelError(message: "Couldn't read the journal: \(error.localizedDescription)"))
            }
        }
    }

    /// Where a session's screenshot is; it may be gone once the day passes retention.
    func screenshot(of session: Session) -> URL {
        dayDir(day(of: session.start)).appending(path: session.representativeFrame)
    }

    func labels(day: String) throws -> [Label] {
        try JournalCoding.decodeLines(Label.self, from: read(dayDir(day).appending(path: "labels.jsonl")))
    }

    /// The app never writes labels.jsonl, so the command line appends to it with the app running.
    func append(_ labels: [Label], day: String) throws {
        guard !labels.isEmpty else { return }
        try appendLine(try labels.map { try JournalCoding.line($0, timeZone: timeZone) }.joined(separator: "\n"),
                       to: dayDir(day).appending(path: "labels.jsonl"))
    }

    /// Drops answers about sessions that no longer exist, after a forget rebuilt the day.
    func pruneLabels(day: String) throws {
        let url = dayDir(day).appending(path: "labels.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let kept = Labeling.kept(try labels(day: day), sessions: try rows(day: day).sessions)
        try jsonl(kept).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Replaces a day's rows; each file is written to a temporary file first, then moved into place.
    /// Only for the command line, with the app quit: the app itself only ever appends.
    func rewrite(day: String, frames: [FrameRecord], events: [EventRecord], sessions: [Session]) throws {
        let dir = dayDir(day)
        try jsonl(frames).write(to: dir.appending(path: "frames.jsonl"), atomically: true, encoding: .utf8)
        try jsonl(events).write(to: dir.appending(path: "events.jsonl"), atomically: true, encoding: .utf8)
        try jsonl(sessions).write(to: dir.appending(path: "sessions.jsonl"), atomically: true, encoding: .utf8)
    }

    /// `images` are paths relative to the day folder; missing files are fine.
    func deleteImages(_ images: [String], day: String) {
        for image in images { try? FileManager.default.removeItem(at: dayDir(day).appending(path: image)) }
    }

    /// Screenshots on disk for one day, as `frames/<id>.heic`.
    func imagesOnDisk(day: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dayDir(day).appending(path: "frames").path)) ?? []
        return names.filter { $0.hasSuffix(".heic") }.sorted().map { "frames/\($0)" }
    }

    /// Bytes taken by some of a day's files, given relative to the day folder.
    func size(day: String, files: [String]) -> Int64 {
        files.reduce(0) { total, file in
            total + Int64((try? dayDir(day).appending(path: file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Every line of the journal's text files that mentions a term, ignoring case and accents, as "path: line".
    func mentions(of terms: [String]) -> [String] {
        let files = dayNames().sorted().flatMap { day in
            ["frames.jsonl", "events.jsonl", "sessions.jsonl", "summary.md", ".digest.json"].map { "days/\(day)/\($0)" }
        } + ["index.md", "week.md"]
        return files.flatMap { file in
            ((try? read(root.appending(path: file))) ?? "").split(separator: "\n")
                .filter { line in terms.contains { line.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
                .map { "\(file): \($0)" }
        }
    }

    /// Rebuilds sessions.jsonl, summary.md and .digest.json for one day, then index.md and week.md.
    func summarize(day: String) throws {
        let dir = dayDir(day)
        let frames = try JournalCoding.decodeLines(FrameRecord.self, from: read(dir.appending(path: "frames.jsonl")))
        let events = try JournalCoding.decodeLines(EventRecord.self, from: read(dir.appending(path: "events.jsonl")))
        let sessions = SessionBuilder.sessions(from: frames)
        let digest = DaySummary.digest(day: day, sessions: sessions, events: events)

        try jsonl(sessions).write(to: dir.appending(path: "sessions.jsonl"), atomically: true, encoding: .utf8)
        try DaySummary.markdown(digest, timeZone: timeZone).write(to: dir.appending(path: "summary.md"), atomically: true, encoding: .utf8)
        try JournalCoding.line(digest, timeZone: timeZone).write(to: digestURL(day), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: dir.appending(path: ".index-line"))
        try writeIndex()
    }

    /// Past days with frames but a missing summary or digest: the Mac was off at midnight,
    /// an older version captured them, or the `forget` skill cleared them for a rebuild.
    func unsummarizedDays(before today: String) -> [String] {
        let fm = FileManager.default
        return dayNames().filter { day in
            day < today && fm.fileExists(atPath: dayDir(day).appending(path: "frames.jsonl").path)
                && !(fm.fileExists(atPath: digestURL(day).path) && fm.fileExists(atPath: dayDir(day).appending(path: "summary.md").path))
        }
    }

    /// Frame rows written for one day.
    func frameCount(day: String) -> Int {
        guard let data = FileManager.default.contents(atPath: dayDir(day).appending(path: "frames.jsonl").path) else { return 0 }
        return data.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
    }

    /// Bytes on disk for one day: screenshots plus logs.
    func size(day: String) -> Int64 {
        let files = FileManager.default.enumerator(at: dayDir(day), includingPropertiesForKeys: [.fileSizeKey])
        return (files?.allObjects as? [URL] ?? []).reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func purge(keepDays: Int, today: String) throws {
        for day in RetentionPolicy.expiredDays(dayNames(), today: today, keep: keepDays) {
            try FileManager.default.removeItem(at: dayDir(day))
        }
        try writeIndex()
    }

    /// index.md and week.md, from each day's digest so older days are never re-parsed.
    private func writeIndex() throws {
        let digests = dayNames().sorted(by: >).compactMap(digest)
        let body = "# Screen Journal\n\nNewest first. Each day links to its summary.\n\n"
            + digests.map(DaySummary.indexLine).joined(separator: "\n") + "\n"
        try body.write(to: root.appending(path: "index.md"), atomically: true, encoding: .utf8)
        try WeekDigest.markdown(digests, endingOn: day(of: Date()), timeZone: timeZone)
            .write(to: root.appending(path: "week.md"), atomically: true, encoding: .utf8)
    }

    private func digest(_ day: String) -> DayDigest? {
        try? JournalCoding.decodeLines(DayDigest.self, from: read(digestURL(day))).first
    }

    private func digestURL(_ day: String) -> URL { dayDir(day).appending(path: ".digest.json") }

    func dayNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: daysDir.path)) ?? []).filter { !$0.hasPrefix(".") }
    }

    private func jsonl<T: Encodable>(_ rows: [T]) throws -> String {
        try rows.map { try JournalCoding.line($0, timeZone: timeZone) + "\n" }.joined()
    }

    private func read(_ url: URL) throws -> String {
        FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
    }

    private func appendLine(_ line: String, to url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
