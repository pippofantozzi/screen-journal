import Foundation

/// What the app binary was asked to do: open the menu bar app, or run one journal command and exit.
public enum Launch: Equatable, Sendable {
    case app
    /// `root` replaces ~/ScreenJournal; for tests against a copy, and then the app is left alone.
    case command(JournalCommand, root: String?)
    case invalid(String)
    /// Usage text, for `--help`.
    case help(String)

    public static func parse(_ arguments: [String], timeZone: TimeZone) -> Launch {
        let words = withoutSystemFlags(Array(arguments.dropFirst()))
        guard let name = words.first(where: JournalCommand.names.contains) else {
            if words.isEmpty { return .app }
            if words.contains(where: ["--help", "-h", "help"].contains) { return .help(JournalCommand.usage) }
            return .invalid("Unknown command: \(words.joined(separator: " "))\n\n\(JournalCommand.usage)")
        }
        var options = Options(words.filter { $0 != name })
        let root = options.take("--root")
        let command = JournalCommand.parse(name, &options, timeZone: timeZone)
        if let error = options.error ?? options.leftover { return .invalid(error) }
        switch command {
        case .success(let command): return .command(command, root: root)
        case .failure(let usage): return .invalid(usage.message)
        }
    }

    /// Finder and Xcode add `-psn_…` and `-NS… value` pairs.
    private static func withoutSystemFlags(_ words: [String]) -> [String] {
        var kept: [String] = []
        var skipValue = false
        for word in words {
            if skipValue { skipValue = false; continue }
            if word.hasPrefix("-psn_") { continue }
            if word.hasPrefix("-NS") { skipValue = true; continue }
            kept.append(word)
        }
        return kept
    }
}

public enum JournalCommand: Equatable, Sendable {
    case forget(Forget.Target, apply: Bool)
    case tidy(keepDays: Int, apply: Bool)
    case rebuild
    /// Asks the decision model about sessions not yet answered under the current `labels.json`; `day` nil means every day.
    case label(day: String?, titlesOnly: Bool, apply: Bool)
    /// Asks the vision model about every session with a screenshot it may see, and keeps each request and reply
    /// in `out` as an eval case; writes no labels.
    case cases(day: String?, out: String, apply: Bool)
    /// Runs a recorded WAV through dictation as if just spoken, and prints the transcript and the text it would type.
    /// With `selection`, as if that text was highlighted.
    case dictate(audio: String, selection: String?, words: [String], language: DictationLanguage)

    public struct Usage: Error, Equatable {
        public let message: String
    }

    static let names: Set<String> = ["forget", "tidy", "rebuild", "label", "cases", "dictate"]

    static let usage = """
    Usage:
      ScreenJournal forget --from 2026-10-21T18:57 --to 2026-10-21T19:00 [--apply]
      ScreenJournal forget --term <word> [--term …] [--apply]
      ScreenJournal tidy --keep-days 7 [--apply]
      ScreenJournal rebuild
      ScreenJournal label [--day 2026-10-21] [--titles-only] [--apply]
      ScreenJournal cases --out <folder> [--day 2026-10-21] [--apply]
      ScreenJournal dictate --audio <file.wav> [--selection <text>] [--word <name> …] [--language portuguese|english|automatic]
    """

    fileprivate static func parse(_ name: String, _ options: inout Options, timeZone: TimeZone) -> Result<JournalCommand, Usage> {
        switch name {
        case "forget": forget(&options, timeZone: timeZone)
        case "tidy": tidy(&options)
        case "label": label(&options)
        case "cases": cases(&options)
        case "dictate": dictate(&options)
        default: .success(.rebuild)
        }
    }

    private static func forget(_ options: inout Options, timeZone: TimeZone) -> Result<JournalCommand, Usage> {
        let apply = options.flag("--apply")
        let terms = options.takeAll("--term").map { $0.trimmingCharacters(in: .whitespaces) }
        let from = options.take("--from"), to = options.take("--to")
        switch (terms.isEmpty, from, to) {
        case (false, nil, nil):
            return terms.contains(where: \.isEmpty) ? fail("A --term can't be blank.") : .success(.forget(.terms(terms), apply: apply))
        case (true, let from?, let to?):
            guard let start = localDate(from, timeZone), let end = localDate(to, timeZone) else {
                return fail("Times look like 2026-10-21T18:57 or 2026-10-21T18:57:30, in local time.")
            }
            return start < end ? .success(.forget(.range(from: start, to: end), apply: apply)) : fail("--from must come before --to.")
        default:
            return fail("forget takes either --from and --to, or one or more --term.")
        }
    }

    private static func tidy(_ options: inout Options) -> Result<JournalCommand, Usage> {
        let apply = options.flag("--apply")
        guard let days = options.take("--keep-days").flatMap(Int.init), days >= 0 else {
            return fail("tidy needs --keep-days with a whole number of days, 0 or more.")
        }
        return .success(.tidy(keepDays: days, apply: apply))
    }

    private static func label(_ options: inout Options) -> Result<JournalCommand, Usage> {
        let apply = options.flag("--apply"), titlesOnly = options.flag("--titles-only")
        return day(&options).map { .label(day: $0, titlesOnly: titlesOnly, apply: apply) }
    }

    private static func cases(_ options: inout Options) -> Result<JournalCommand, Usage> {
        let apply = options.flag("--apply")
        guard let out = options.take("--out"), !out.isEmpty else { return fail("cases needs --out with a folder to keep them in.") }
        return day(&options).map { .cases(day: $0, out: out, apply: apply) }
    }

    private static func dictate(_ options: inout Options) -> Result<JournalCommand, Usage> {
        let words = options.takeAll("--word"), selection = options.take("--selection")
        let spoken = options.take("--language")
        guard let audio = options.take("--audio"), !audio.isEmpty else { return fail("dictate needs --audio with a WAV file.") }
        guard let language = spoken.map(DictationLanguage.init(rawValue:)) ?? .default else {
            return fail("--language is portuguese, english or automatic.")
        }
        return .success(.dictate(audio: audio, selection: selection, words: words, language: language))
    }

    /// nil when not given; every day.
    private static func day(_ options: inout Options) -> Result<String?, Usage> {
        let day = options.take("--day")
        if let day, day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) == nil {
            return .failure(Usage(message: "--day looks like 2026-10-21.\n\n" + usage))
        }
        return .success(day)
    }

    private static func localDate(_ text: String, _ timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func fail(_ message: String) -> Result<JournalCommand, Usage> {
        .failure(Usage(message: message + "\n\n" + usage))
    }
}

/// `--name value` pairs and bare flags, consumed as they're read so anything left over is an error.
private struct Options {
    private var words: [String]
    private(set) var error: String?

    init(_ words: [String]) { self.words = words }

    var leftover: String? {
        words.isEmpty ? nil : "Unexpected: \(words.joined(separator: " "))\n\n\(JournalCommand.usage)"
    }

    mutating func flag(_ name: String) -> Bool {
        guard let i = words.firstIndex(of: name) else { return false }
        words.remove(at: i)
        return true
    }

    mutating func take(_ name: String) -> String? {
        takeAll(name).last
    }

    mutating func takeAll(_ name: String) -> [String] {
        var values: [String] = []
        while let i = words.firstIndex(of: name) {
            guard i + 1 < words.count, !words[i + 1].hasPrefix("--") else {
                error = "\(name) needs a value.\n\n\(JournalCommand.usage)"
                words.remove(at: i)
                continue
            }
            values.append(words[i + 1])
            words.removeSubrange(i...i + 1)
        }
        return values
    }
}
