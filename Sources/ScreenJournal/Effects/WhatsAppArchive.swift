import Foundation
import JournalCore

/// Writes a chat's last messages as `<chat> <date>.zip` holding a folder of `chat.txt`, the media files
/// and a transcript beside each voice note.
enum WhatsAppArchive {
    struct Saved: Equatable {
        let zip: URL
        let messages: Int
        /// Media never downloaded to this Mac, written as "image omitted" and the like.
        let missing: Int
        /// Voice notes the transcriber couldn't hear: no gateway key, or it failed.
        let untranscribed: Int
    }

    enum Failure: Error, Equatable {
        case store(WhatsAppStore.Failure)
        case writing(String)
    }

    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    /// Voice notes at once; each takes a second or two.
    private static let parallelTranscriptions = 6

    static func save(_ chat: WhatsApp.Chat, last count: Int, to folder: URL = downloads) async -> Result<Saved, Failure> {
        let messages: [WhatsApp.Message]
        switch WhatsAppStore.messages(in: chat, last: count) {
        case .success(let found): messages = found
        case .failure(let failure): return .failure(.store(failure))
        }
        let voiceNotes = WhatsApp.voiceNotes(in: messages)
        let heard = await transcribe(voiceNotes)
        let export = WhatsApp.export(messages, chat: chat.name, timeZone: .current, transcripts: heard)
        let name = WhatsApp.archiveName(chat: chat.name, at: Date(), timeZone: .current)
        return write(export, named: name, to: folder).map {
            Saved(zip: $0, messages: messages.count, missing: export.missing, untranscribed: voiceNotes.count - heard.count)
        }
    }

    /// Transcripts by voice note, in whatever language each was spoken; ones that failed or said nothing are left out.
    private static func transcribe(_ voiceNotes: [String]) async -> [String: String] {
        guard !voiceNotes.isEmpty, let gateway = SpeechGateway.configured() else { return [:] }
        let words = Preferences.currentDictationWords
        return await withTaskGroup(of: (String, String?).self) { group in
            var pending = voiceNotes.makeIterator()
            func next() {
                guard let file = pending.next() else { return }
                group.addTask {
                    guard let audio = try? Data(contentsOf: WhatsAppStore.messageFolder.appending(path: file)) else { return (file, nil) }
                    let heard = await gateway.transcribe(audio, mediaType: Transcription.mediaType(ofFile: file), words: words,
                                                         language: .automatic, timeout: 120)
                    return (file, try? heard.get())
                }
            }
            for _ in 0..<parallelTranscriptions { next() }
            var heard: [String: String] = [:]
            for await (file, text) in group {
                if let text, !text.isEmpty { heard[file] = text }
                next()
            }
            return heard
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
            for transcript in export.transcripts {
                try transcript.text.write(to: contents.appending(path: transcript.name), atomically: true, encoding: .utf8)
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
