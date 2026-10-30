import Foundation
import JournalCore

/// Writes a chat's last messages as `<chat> <date>.zip` holding a folder of `chat.txt` and the media files.
enum WhatsAppArchive {
    struct Saved: Equatable {
        let zip: URL
        let messages: Int
        /// Media never downloaded to this Mac, written as "image omitted" and the like.
        let missing: Int
    }

    enum Failure: Error, Equatable {
        case store(WhatsAppStore.Failure)
        case writing(String)
    }

    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    static func save(_ chat: WhatsApp.Chat, last count: Int, to folder: URL = downloads) -> Result<Saved, Failure> {
        WhatsAppStore.messages(in: chat, last: count).mapError(Failure.store).flatMap { messages in
            let export = WhatsApp.export(messages, chat: chat.name, timeZone: .current)
            let name = WhatsApp.archiveName(chat: chat.name, at: Date(), timeZone: .current)
            return write(export, named: name, to: folder).map { Saved(zip: $0, messages: messages.count, missing: export.missing) }
        }
    }

    /// Builds the folder in a temporary place and zips it with `ditto`, as Finder's Compress does.
    private static func write(_ export: WhatsApp.Export, named name: String, to folder: URL) -> Result<URL, Failure> {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appending(path: UUID().uuidString)
        let contents = staging.appending(path: name)
        defer { try? files.removeItem(at: staging) }
        let zip = folder.appending(path: "\(name).zip")
        do {
            try files.createDirectory(at: contents, withIntermediateDirectories: true)
            try export.transcript.write(to: contents.appending(path: "chat.txt"), atomically: true, encoding: .utf8)
            for file in export.files {
                try files.copyItem(at: WhatsAppStore.messageFolder.appending(path: file.source), to: contents.appending(path: file.name))
            }
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", contents.path, zip.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { return .failure(.writing("ditto exited with \(ditto.terminationStatus)")) }
        } catch {
            return .failure(.writing(error.localizedDescription))
        }
        return .success(zip)
    }
}
