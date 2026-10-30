import Foundation
import JournalCore
import SQLite3

/// Reads the WhatsApp Mac app's own database, read-only. macOS may ask once to let Screen Journal see another app's data.
/// Only media the Mac app downloaded is on disk.
struct WhatsAppStore {
    enum Failure: Error, Equatable {
        case notInstalled
        case unreadable(String)
    }

    static let container = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/group.net.whatsapp.WhatsApp.shared")

    /// Where `WhatsApp.Media.file` paths start.
    static let messageFolder = container.appending(path: "Message")

    /// Core Data dates count from 2001.
    private static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    /// One-to-one chats and groups, most recent first.
    static func chats() -> Result<[WhatsApp.Chat], Failure> {
        query("""
            SELECT Z_PK, ZPARTNERNAME, ZLASTMESSAGEDATE FROM ZWACHATSESSION
            WHERE ZSESSIONTYPE IN (0, 1) AND ZREMOVED = 0 AND ZPARTNERNAME IS NOT NULL
            ORDER BY ZLASTMESSAGEDATE DESC
            """) { row in
            WhatsApp.Chat(id: row.int(0), name: row.text(1) ?? "", lastMessage: epoch.addingTimeInterval(row.double(2)))
        }
    }

    /// The chat's last `count` messages that have something to export, oldest first.
    /// A group member is named as saved in WhatsApp's contacts, else by their profile name;
    /// `ZCONTACTNAME` is empty and a message's `ZPUSHNAME` is encoded.
    static func messages(in chat: WhatsApp.Chat, last count: Int) -> Result<[WhatsApp.Message], Failure> {
        query("""
            SELECT m.ZMESSAGEDATE, m.ZISFROMME, m.ZMESSAGETYPE, m.ZTEXT, i.ZTITLE, i.ZMEDIALOCALPATH,
                   CASE WHEN g.Z_PK IS NOT NULL THEN COALESCE(
                       (SELECT ZFULLNAME FROM contacts.ZWAADDRESSBOOKCONTACT WHERE ZLID = g.ZMEMBERJID OR ZWHATSAPPID = g.ZMEMBERJID LIMIT 1),
                       (SELECT ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID = g.ZMEMBERJID LIMIT 1),
                       'Unknown') END
            FROM ZWAMESSAGE m
            LEFT JOIN ZWAMEDIAITEM i ON i.Z_PK = m.ZMEDIAITEM
            LEFT JOIN ZWAGROUPMEMBER g ON g.Z_PK = m.ZGROUPMEMBER
            WHERE m.ZCHATSESSION = \(chat.id) AND m.ZMESSAGETYPE IN (\(WhatsApp.exportedTypes.map(String.init).joined(separator: ",")))
            ORDER BY m.ZMESSAGEDATE DESC LIMIT \(max(0, count))
            """) { row -> WhatsApp.Message in
            var media: WhatsApp.Media?
            if case .media(let kind) = WhatsApp.content(ofType: Int(row.int(2))) {
                let file = row.text(5).flatMap { FileManager.default.fileExists(atPath: messageFolder.appending(path: $0).path) ? $0 : nil }
                media = WhatsApp.Media(kind: kind, file: file)
            }
            return WhatsApp.Message(
                date: epoch.addingTimeInterval(row.double(0)),
                from: row.int(1) == 1 ? .you : .member(row.text(6)),
                text: row.text(3) ?? row.text(4),
                media: media
            )
        }.map { $0.reversed() }
    }

    // MARK: SQLite

    struct Row {
        let statement: OpaquePointer
        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func text(_ column: Int32) -> String? { sqlite3_column_text(statement, column).map { String(cString: $0) } }
    }

    /// Read-only but WAL-aware, so the latest messages count even before WhatsApp checkpoints them.
    private static func query<T>(_ sql: String, _ read: (Row) -> T) -> Result<[T], Failure> {
        let file = container.appending(path: "ChatStorage.sqlite")
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.notInstalled) }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let contacts = container.appending(path: "ContactsV2.sqlite").path.replacingOccurrences(of: "'", with: "''")
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_exec(db, "ATTACH DATABASE '\(contacts)' AS contacts", nil, nil, nil) == SQLITE_OK
        else {
            return .failure(.unreadable(String(cString: sqlite3_errmsg(db))))
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .failure(.unreadable(String(cString: sqlite3_errmsg(db))))
        }
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(read(Row(statement: statement))) }
        return .success(rows)
    }
}
