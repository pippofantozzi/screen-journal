import CoreGraphics
import Foundation
import JournalCore

/// The journal folder on disk. Every file write in the app goes through here.
struct JournalStore {
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

    /// Writes CLAUDE.md and the skill unless an up-to-date copy is already there.
    func installGuide() throws {
        for file in JournalGuide.files {
            let url = root.appending(path: file.path)
            if let existing = try? String(contentsOf: url, encoding: .utf8), JournalGuide.isCurrent(existing) { continue }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Rebuilds sessions.jsonl, summary.md and the index line for one day, then index.md.
    func summarize(day: String) throws {
        let dir = dayDir(day)
        let frames = try JournalCoding.decodeLines(FrameRecord.self, from: read(dir.appending(path: "frames.jsonl")))
        let events = try JournalCoding.decodeLines(EventRecord.self, from: read(dir.appending(path: "events.jsonl")))
        let sessions = SessionBuilder.sessions(from: frames)
        let digest = DaySummary.digest(day: day, sessions: sessions, events: events)

        try sessions.map { try JournalCoding.line($0, timeZone: timeZone) }.joined(separator: "\n")
            .write(to: dir.appending(path: "sessions.jsonl"), atomically: true, encoding: .utf8)
        try DaySummary.markdown(digest, timeZone: timeZone).write(to: dir.appending(path: "summary.md"), atomically: true, encoding: .utf8)
        try DaySummary.indexLine(digest).write(to: dir.appending(path: ".index-line"), atomically: true, encoding: .utf8)
        try writeIndex()
    }

    /// Days that have frames but no summary yet, e.g. after the Mac was off at midnight.
    func unsummarizedDays(before today: String) -> [String] {
        dayNames().filter { $0 < today && !FileManager.default.fileExists(atPath: dayDir($0).appending(path: "summary.md").path) }
    }

    func purge(keepDays: Int, today: String) throws {
        for day in RetentionPolicy.expiredDays(dayNames(), today: today, keep: keepDays) {
            try FileManager.default.removeItem(at: dayDir(day))
        }
        try writeIndex()
    }

    private func writeIndex() throws {
        let lines = dayNames().sorted(by: >).compactMap { try? read(dayDir($0).appending(path: ".index-line")) }
        let body = "# Screen Journal\n\nNewest first. Each day links to its summary.\n\n" + lines.joined(separator: "\n") + "\n"
        try body.write(to: root.appending(path: "index.md"), atomically: true, encoding: .utf8)
    }

    private func dayNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: daysDir.path)) ?? []
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
