import Darwin
import Foundation
import JournalCore

/// Owner-only persistence and cross-process file locking for Keep Awake state and recovery backstop.
enum AwakeStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: AwakeIPC.supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Runs `body` while holding an exclusive `flock` shared with the launchd backstop process.
    static func withLock<T>(timeout: TimeInterval = 3.0, _ body: () throws -> T) throws -> T {
        try ensureDirectory()
        let path = AwakeIPC.lockFileURL.path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Couldn't open Keep Awake lock file.",
            ])
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK && errno != EINTR {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                    NSLocalizedDescriptionKey: "Couldn't lock Keep Awake state.",
                ])
            }
            if Date() >= deadline {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EWOULDBLOCK), userInfo: [
                    NSLocalizedDescriptionKey: "Keep Awake recovery lock is busy; try again in a moment.",
                ])
            }
            usleep(50_000)
        }
        return try body()
    }

    static func readSession() -> AwakeSession? {
        guard let data = try? Data(contentsOf: AwakeIPC.sessionFileURL) else { return nil }
        return try? decoder.decode(AwakeSession.self, from: data)
    }

    static func writeSession(_ session: AwakeSession) throws {
        try ensureDirectory()
        let data = try encoder.encode(session)
        try data.write(to: AwakeIPC.sessionFileURL, options: .atomic)
    }

    static func removeSession() {
        try? FileManager.default.removeItem(at: AwakeIPC.sessionFileURL)
    }

    static func readJournal() -> AwakeJournal {
        guard let data = try? Data(contentsOf: AwakeIPC.journalFileURL),
              let journal = try? decoder.decode(AwakeJournal.self, from: data)
        else { return AwakeJournal() }
        return journal
    }

    static func writeJournal(_ journal: AwakeJournal) throws {
        try ensureDirectory()
        let data = try encoder.encode(journal)
        try data.write(to: AwakeIPC.journalFileURL, options: .atomic)
    }

    static func readStatus() -> AwakeStatusSnapshot? {
        guard let data = try? Data(contentsOf: AwakeIPC.statusFileURL) else { return nil }
        return try? decoder.decode(AwakeStatusSnapshot.self, from: data)
    }

    static func writeStatus(_ status: AwakeStatusSnapshot) {
        try? ensureDirectory()
        guard let data = try? encoder.encode(status) else { return }
        try? data.write(to: AwakeIPC.statusFileURL, options: .atomic)
    }
}
