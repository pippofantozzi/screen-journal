import Foundation

/// A WhatsApp chat's last messages as a folder WhatsApp's own "Export chat" would make:
/// `chat.txt` in its format, plus each downloaded photo, video, voice note or file beside it,
/// and each voice note's transcript as a `.txt` of the same name.
public enum WhatsApp {
    public struct Chat: Equatable, Hashable, Identifiable, Sendable {
        public let id: Int64
        public let name: String
        public let lastMessage: Date

        public init(id: Int64, name: String, lastMessage: Date) {
            self.id = id
            self.name = name
            self.lastMessage = lastMessage
        }
    }

    public enum Sender: Equatable, Sendable {
        case you
        /// A group member's name; nil in a one-to-one chat, where it's the chat's name.
        case member(String?)
    }

    public enum MediaKind: String, Sendable {
        case photo = "PHOTO", video = "VIDEO", audio = "AUDIO", document = "DOCUMENT", gif = "GIF", sticker = "STICKER"

        /// How WhatsApp's export writes media it didn't include.
        var omitted: String {
            switch self {
            case .gif: "GIF omitted"
            case .photo: "image omitted"
            default: "\(rawValue.lowercased()) omitted"
            }
        }
    }

    public struct Media: Equatable, Sendable {
        public let kind: MediaKind
        /// Relative to WhatsApp's `Message` folder; nil when it was never downloaded to this Mac.
        public let file: String?

        public init(kind: MediaKind, file: String?) {
            self.kind = kind
            self.file = file
        }
    }

    public struct Message: Equatable, Sendable {
        public let date: Date
        public let from: Sender
        /// The message, or a photo's caption.
        public let text: String?
        public let media: Media?

        public init(date: Date, from: Sender, text: String?, media: Media?) {
            self.date = date
            self.from = from
            self.text = text
            self.media = media
        }
    }

    public enum Content: Equatable, Sendable {
        case text
        case media(MediaKind)
    }

    /// `ZMESSAGETYPE` in WhatsApp's ChatStorage.sqlite; calls, system notices, polls and the like have no content to export.
    public static func content(ofType type: Int) -> Content? {
        switch type {
        case 0, 7: .text
        case 1: .media(.photo)
        case 2: .media(.video)
        case 3: .media(.audio)
        case 8: .media(.document)
        case 11: .media(.gif)
        case 15: .media(.sticker)
        default: nil
        }
    }

    public static let exportedTypes: [Int] = [0, 1, 2, 3, 7, 8, 11, 15]

    /// The chat whose header reads `name`; WhatsApp sprinkles direction marks into names, and two chats can share one.
    public static func chat(named name: String?, among chats: [Chat]) -> Chat? {
        guard let name else { return nil }
        let wanted = plain(name).lowercased()
        return chats.filter { plain($0.name).lowercased() == wanted }.max { $0.lastMessage < $1.lastMessage }
    }

    public struct Attachment: Equatable, Sendable {
        /// Relative to WhatsApp's `Message` folder.
        public let source: String
        public let name: String

        public init(source: String, name: String) {
            self.source = source
            self.name = name
        }
    }

    /// A voice note's words, named after its audio file.
    public struct VoiceTranscript: Equatable, Sendable {
        public let name: String
        public let text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public struct Export: Equatable, Sendable {
        public let transcript: String
        public let files: [Attachment]
        public let transcripts: [VoiceTranscript]
        /// Media in the transcript that was never downloaded to this Mac.
        public let missing: Int
    }

    /// The downloaded voice notes among `messages`, as `WhatsApp.Media.file` paths, to transcribe before exporting.
    public static func voiceNotes(in messages: [Message]) -> [String] {
        messages.compactMap { $0.media?.kind == .audio ? $0.media?.file : nil }
    }

    /// `messages` oldest first; `transcripts` keyed by a voice note's `WhatsApp.Media.file`.
    public static func export(_ messages: [Message], chat: String, timeZone: TimeZone, transcripts heard: [String: String] = [:]) -> Export {
        var lines: [String] = [], files: [Attachment] = [], transcripts: [VoiceTranscript] = [], missing = 0
        for message in messages {
            let sender = switch message.from {
            case .you: "You"
            case .member(let name): plain(name ?? chat)
            }
            var body = message.text ?? ""
            if let media = message.media {
                if let file = media.file {
                    let name = String(format: "%08d-%@-%@", files.count + 1, media.kind.rawValue, stamp(message.date, "yyyy-MM-dd-HH-mm-ss", timeZone))
                        + extensionOf(file)
                    files.append(Attachment(source: file, name: name))
                    body = "<attached: \(name)>" + (body.isEmpty ? "" : " \(body)")
                    if let text = heard[file], !text.isEmpty {
                        transcripts.append(VoiceTranscript(name: (name as NSString).deletingPathExtension + ".txt", text: text + "\n"))
                        body += "\nTranscript: \(text)"
                    }
                } else {
                    missing += 1
                    body = media.kind.omitted + (body.isEmpty ? "" : " \(body)")
                }
            }
            lines.append("[\(stamp(message.date, "dd/MM/yyyy, HH:mm:ss", timeZone))] \(sender): \(body)\n")
        }
        return Export(transcript: lines.joined(), files: files, transcripts: transcripts, missing: missing)
    }

    /// The zip's and its folder's name: safe for Finder, unique to the minute.
    public static func archiveName(chat: String, at date: Date, timeZone: TimeZone) -> String {
        let safe = plain(chat).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe) \(stamp(date, "yyyy-MM-dd HH.mm", timeZone))"
    }

    /// Without the invisible direction marks WhatsApp wraps around names and phone numbers.
    static func plain(_ text: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                                          "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { !marks.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func extensionOf(_ file: String) -> String {
        let ext = (file as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    private static func stamp(_ date: Date, _ format: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
