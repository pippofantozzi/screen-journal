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

    /// Already-transcribed chunks for a saved recording, so retrying a multi-piece recording only re-sends failed pieces.
    static func chunks(for wavURL: URL) -> [Int: String] {
        guard let data = try? Data(contentsOf: chunkURL(for: wavURL)),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var result: [Int: String] = [:]
        for (key, value) in raw {
            if let index = Int(key) { result[index] = value }
        }
        return result
    }

    static func saveChunks(_ chunks: [Int: String], for wavURL: URL) {
        guard !chunks.isEmpty else { return }
        let keyed = Dictionary(uniqueKeysWithValues: chunks.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(keyed) else { return }
        try? data.write(to: chunkURL(for: wavURL), options: .atomic)
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: chunkURL(for: url))
    }

    static func discardNewest() {
        if let newest = all().first { discard(newest) }
    }

    private static func chunkURL(for wavURL: URL) -> URL {
        wavURL.deletingPathExtension().appendingPathExtension("chunks.json")
    }
}
