import Foundation

/// Dictations whose text hasn't been pasted yet, kept on disk so a dropped connection, or a quit, doesn't lose what she said.
/// Each one is removed once its text is pasted; only the newest few stay. Kept apart from the journal, which never holds audio.
enum UnsentRecordings {
    static let kept = 3
    static let folder = URL.applicationSupportDirectory.appending(path: "ScreenJournal/Unsent Dictations")

    /// Where it was saved, or nil when the disk refused.
    static func keep(_ wav: Data, at date: Date = Date()) -> URL? {
        let url = folder.appending(path: "\(Int(date.timeIntervalSince1970 * 1000)).wav")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try wav.write(to: url, options: .atomic)
        } catch { return nil }
        for old in all().dropFirst(kept) { discard(old) }
        return url
    }

    /// Newest first: names are the moment each was saved, in milliseconds.
    static func all() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".wav") }.sorted(by: >).map { folder.appending(path: $0) }
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
