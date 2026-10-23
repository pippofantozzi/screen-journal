import Foundation

public struct LabelError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// A kind of task the model files a session under.
public struct TaskKind: Codable, Equatable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

/// `labels.json` in the journal root: what the model is told about her work, the task kinds she picked,
/// and whether screenshots may be sent.
public struct LabelSetup: Codable, Equatable, Sendable {
    /// Her own words, e.g. "I do marketing for clients, so Instagram is usually work."
    public var about: String
    /// The suggestions she clicked, under their English names, and her own; a name alone is enough.
    /// The fewer, the sharper the sorting.
    public var picked: [String]
    /// On unless she turns it off: with the screenshot, four in five sessions were sorted right, against two in three from text alone.
    /// Never for a session where something on screen was redacted, since pixels can't be.
    public var screenshots: Bool

    public init(about: String = "", picked: [String] = [], screenshots: Bool = true) {
        self.about = about
        self.picked = picked
        self.screenshots = screenshots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        about = try container.decode(String.self, forKey: .about)
        picked = try container.decodeIfPresent([String].self, forKey: .picked)
            ?? Self.picked(fromOldTasks: try container.decodeIfPresent([String].self, forKey: .tasks) ?? [])
        screenshots = try container.decodeIfPresent(Bool.self, forKey: .screenshots) ?? true
    }

    private enum CodingKeys: String, CodingKey { case about, picked, tasks, screenshots }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(about, forKey: .about)
        try container.encode(picked, forKey: .picked)
        try container.encode(screenshots, forKey: .screenshots)
    }

    /// Old files listed her own kinds beside suggestions that were always on: they keep every one.
    private static func picked(fromOldTasks tasks: [String]) -> [String] {
        tasks.isEmpty ? [] : TaskKind.suggestions.map(\.name) + tasks
    }

    public static func parse(_ text: String) -> Result<LabelSetup, LabelError> {
        guard let setup = try? JSONDecoder().decode(LabelSetup.self, from: Data(text.utf8)) else {
            return .failure(LabelError(message: #"labels.json isn't valid: expected {"about": "…", "picked": ["…"]}."#))
        }
        return .success(setup)
    }

    public func file() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self) + "\n"
    }

    /// Her picks with one more at the end, trimmed, a suggestion under its own name; blank or already there (any case) changes nothing.
    public static func adding(_ kind: String, to picked: [String]) -> [String] {
        let name = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, included(name, in: picked) == nil else { return picked }
        return picked + [TaskKind.suggestion(named: name)?.name ?? name]
    }

    /// The pick, or `other`, that already covers this name, any case.
    public static func included(_ kind: String, in picked: [String]) -> String? {
        let name = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        return (picked + [TaskKind.other.name]).first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// What the model chooses among: her picks once each by lowercased name, every suggestion until she picks, then `other`.
    public var kinds: [TaskKind] {
        var seen = Set([TaskKind.other.name])
        let hers = picked
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { TaskKind.suggestion(named: $0) ?? TaskKind(name: $0, description: $0) }
        return (hers.isEmpty ? TaskKind.suggestions : hers) + [TaskKind.other]
    }

    /// FNV-1a over everything the model is told: rewording a question or editing `about` or the tasks asks every session again.
    public var def: String {
        let told = [about, Questions.work, Questions.automatable, Questions.task] + Questions.handoff + kinds.map { "\($0.name):\($0.description)" }
        let hash = told.joined(separator: "\u{1}").utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }
}

extension TaskKind {
    /// What the work is, not how an agent would do it: that is `automatable`'s question.
    public static let suggestions: [TaskKind] = [
        ("design", "visual design, images, video, layouts"),
        ("content", "writing or editing posts, captions, docs, copy"),
        ("planning", "plans, calendars, briefs, deciding what to do"),
        ("meeting", "a video call or meeting"),
        ("communication", "chats and email with people"),
        ("outreach", "prospecting, sales, posting or replying to audiences"),
        ("research", "reading, searching, learning for a task"),
        ("admin", "accounts, settings and dashboards of any tool, permissions, forms, files, payments"),
        ("building", "writing code, or directing coding agents in a terminal or editor"),
        ("leisure", "entertainment, personal browsing"),
    ].map { TaskKind(name: $0.0, description: $0.1) }

    /// Always there, so a session that fits none of her picks isn't forced into one.
    public static let other = TaskKind(name: "other", description: "anything that fits none of the others")

    public static func suggestion(named name: String) -> TaskKind? {
        suggestions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// The three questions asked about every session; tuned on real sessions.
public enum Questions {
    /// "As opposed to" gives it the other side: without it, work hovered near 0.5 whenever her description was missing.
    static let work = "Is this the person's own work, as opposed to their personal life or leisure? Use what they say about their work. "
        + "Social media, chats and videos can be work when they're about it."
    static let automatable = "Assume the person has AI agents: Claude Code or Codex with skills and scripts, browser-use and computer-use agents "
        + "that click and type in any app, and scheduled jobs. How much of the person's own effort here could those take over? "
        + "Judge the task, not the app. If an agent already does the work and the person is directing or reviewing it, "
        + "rate only how much of that directing could be handed off too: answering an agent's question, approving a plan or "
        + "choosing between options is nothing or a little; telling it to continue, commit or run tests, or watching a build or deploy, "
        + "is mostly or fully. Leisure, personal chats and an idle screen are nothing: there is no work of theirs to hand off."
    /// Scored 0 to 3; the label keeps it as 0 to 1.
    static let handoff = [
        "nothing: needs their own judgment, taste or presence",
        "a little: an agent could prepare or check parts",
        "mostly: an agent could do it and they review",
        "fully: an agent or script could do it unattended",
    ]
    static let task = "Which kind of task is the person doing? Judge by what they are doing in the frontmost app, not by what an image "
        + "on screen shows. Permission prompts and system dialogs are admin. If the screen is blank or still loading, go by the window "
        + "title and app. A chat with an AI assistant or bot is not communication; communication is with people."
}

/// The answers about one session, keyed by its start. `agent` rows are corrections and beat the model's;
/// `look` rows were answered with the screenshot and beat text-only ones.
public struct Label: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case model, look, agent

        var rank: Int {
            switch self {
            case .model: 0
            case .look: 1
            case .agent: 2
            }
        }
    }

    public let session: Date
    /// Probability this is her work.
    public let work: Double
    /// 0 nothing could be handed off, 1 an agent could do it unattended.
    public let automatable: Double
    public let task: String
    /// `LabelSetup.def` when asked.
    public let def: String
    public let source: Source

    public init(session: Date, work: Double, automatable: Double, task: String, def: String, source: Source) {
        self.session = session
        self.work = work
        self.automatable = automatable
        self.task = task
        self.def = def
        self.source = source
    }
}

/// What the decision model sees of one session: who she is, where she was and for how long, what came either side, some of the text.
public struct SessionState: Encodable, Equatable, Sendable {
    public let about: String
    public let app: String
    public let window: String
    public let seconds: Int
    /// The sessions either side, so a copy from one app into another reads as one task.
    public let before: String
    public let after: String
    public let screenText: String
    /// Set when the request carries the screenshot; the state then points at it.
    public internal(set) var screenshot = false
    /// Something on screen was redacted during the session, so its screenshot must not be sent. Not part of the request.
    public let secretOnScreen: Bool

    private enum CodingKeys: String, CodingKey {
        case about = "about_the_person", app, window, seconds = "seconds_on_screen", before, after, screenText = "screen_text", screenshot
    }

    /// `textLimit` 0 sends app, titles and durations only.
    public init(_ session: Session, before: Session? = nil, after: Session? = nil, about: String = "", frames: [FrameRecord], textLimit: Int = 600) {
        self.about = about
        app = session.app ?? "Unknown"
        window = session.windowTitle ?? ""
        seconds = Int(session.duration)
        self.before = Self.glance(before)
        self.after = Self.glance(after)
        let own = frames.filter { $0.focused && $0.bundleID == session.bundleID && $0.start >= session.start && $0.start < session.end }
        let lines = own
            .sorted { $0.start < $1.start }
            .flatMap { $0.text.map { $0.components(separatedBy: "\n") } ?? $0.newLines ?? [] }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Again here for frames captured before redaction existed.
        let text = Secrets.redact(lines.joined(separator: "\n"))
        secretOnScreen = own.contains { $0.secretOnScreen == true } || text.contains(Secrets.placeholder)
        screenText = String(text.prefix(textLimit))
    }

    /// Nothing of hers, for checking that a key works.
    public static let probe = SessionState(
        Session(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60), app: "Notes", bundleID: nil,
                windowTitle: "Shopping list", frames: 1, representativeFrame: ""),
        frames: [])

    private static func glance(_ session: Session?) -> String {
        guard let session else { return "nothing" }
        return "\(session.app ?? "Unknown") — \(session.windowTitle ?? "") (\(Int(session.duration))s)"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !about.isEmpty { try container.encode(about, forKey: .about) }
        try container.encode(app, forKey: .app)
        try container.encode(window, forKey: .window)
        try container.encode(seconds, forKey: .seconds)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
        if !screenText.isEmpty { try container.encode(screenText, forKey: .screenText) }
        if screenshot { try container.encode(SystemOne.screenshotReference, forKey: .screenshot) }
    }
}

/// The wire format of a "System One" decision model: one state, three questions, answered in one pass.
public enum SystemOne {
    public struct Answers: Equatable, Sendable {
        public let work: Double
        public let automatable: Double
        public let task: String
    }

    private struct Request: Encodable {
        struct Question: Encodable {
            let type: String
            let instructions: String
            let criteria: Criteria?
        }
        enum Criteria: Encodable {
            case scale([String])
            case choices([String: String])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .scale(let steps): try container.encode(steps)
                case .choices(let kinds): try container.encode(kinds)
                }
            }
        }
        struct Gateway: Encodable { let gateway: [String: Bool] }
        struct Asset: Encodable {
            let type = "image"
            let data_base64: String
            let format = "jpeg"
        }

        let model: String
        let state: SessionState
        let questions: [String: Question]
        let assets: [String: Asset]?
        let providerOptions: Gateway
    }

    private struct Response: Decodable {
        struct Answer: Decodable {
            let noul: Double?
            let score: Double?
            let choice: String?
        }
        let answers: [String: Answer]
    }

    /// Where the state points at the screenshot; the service puts the image there.
    static let screenshotReference = "<<screen>>"

    /// `providerOptions` asks the gateway to route only to providers that don't train on prompts,
    /// and with `zeroRetention` only to ones that keep nothing (a Vercel Pro feature).
    /// `screenshot` is a JPEG whose long side is at most 1568 pixels, the most the vision model accepts.
    public static func request(model: String, state: SessionState, kinds: [TaskKind], zeroRetention: Bool, screenshot: Data? = nil) throws -> Data {
        var gateway = ["disallowPromptTraining": true]
        if zeroRetention { gateway["zeroDataRetention"] = true }
        let questions = [
            "work": Request.Question(type: "noul", instructions: Questions.work, criteria: nil),
            "automatable": Request.Question(type: "score", instructions: Questions.automatable, criteria: .scale(Questions.handoff)),
            "task": Request.Question(type: "choice", instructions: Questions.task,
                                     criteria: .choices(Dictionary(uniqueKeysWithValues: kinds.map { ($0.name, $0.description) }))),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var state = state
        state.screenshot = screenshot != nil
        let assets = screenshot.map { ["screen": Request.Asset(data_base64: $0.base64EncodedString())] }
        return try encoder.encode(Request(model: model, state: state, questions: questions, assets: assets, providerOptions: .init(gateway: gateway)))
    }

    public static func answers(_ data: Data) -> Result<Answers, LabelError> {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .failure(LabelError(message: "Unexpected reply: \(String(decoding: data.prefix(200), as: UTF8.self))"))
        }
        guard let work = response.answers["work"]?.noul,
              let score = response.answers["automatable"]?.score,
              let task = response.answers["task"]?.choice
        else { return .failure(LabelError(message: "Missing an answer: \(String(decoding: data.prefix(200), as: UTF8.self))")) }
        let steps = Double(Questions.handoff.count - 1)
        return .success(Answers(work: work, automatable: min(max(score / steps, 0), 1), task: task))
    }
}

/// Which sessions still need asking, and what the answers add up to.
public enum Labeling {
    /// Time per kind of task; `handoff` is the share of it agents could take over, counting work only.
    public struct TaskTime: Equatable, Sendable {
        public let task: String
        public let seconds: TimeInterval
        public let work: TimeInterval
        public let handoff: TimeInterval
    }

    /// One window's time and how much of it agents could take over: where to look first for something to automate.
    public struct Candidate: Equatable, Sendable {
        public let app: String
        public let window: String
        public let task: String
        public let seconds: TimeInterval
        public let handoff: TimeInterval
        public let sessions: Int
    }

    /// The answer that stands per session: a correction, else one that saw the screenshot, else the latest;
    /// answers asked under another setup are dropped.
    public static func current(_ labels: [Label], def: String) -> [Date: Label] {
        var current: [Date: Label] = [:]
        for label in labels where label.def == def {
            if let standing = current[label.session], standing.source.rank > label.source.rank { continue }
            current[label.session] = label
        }
        return current
    }

    public static func pending(sessions: [Session], labels: [Label], def: String) -> [Session] {
        let answered = current(labels, def: def)
        return sessions.filter { answered[$0.start] == nil }
    }

    /// The screenshot may go: nothing on screen was redacted, since a key would leave as pixels.
    public static func wantsLook(_ state: SessionState) -> Bool {
        !state.secretOnScreen
    }

    /// How long after its last frame a session counts as over.
    public static let quiet: TimeInterval = 300

    /// Sessions over by `now`: one that ended in the last few minutes may still be growing, and its answer would cover part of it.
    public static func finished(_ sessions: [Session], at now: Date, quiet: TimeInterval = quiet) -> [Session] {
        sessions.filter { $0.end <= now - quiet }
    }

    /// Sessions whose standing answer hasn't seen the screenshot yet.
    public static func unseen(sessions: [Session], labels: [Label], def: String) -> [Session] {
        let answered = current(labels, def: def)
        return sessions.filter { (answered[$0.start]?.source.rank ?? 0) < Label.Source.look.rank }
    }

    /// Answers about sessions that still exist, for after a forget rebuilt them.
    public static func kept(_ labels: [Label], sessions: [Session]) -> [Label] {
        let starts = Set(sessions.map(\.start))
        return labels.filter { starts.contains($0.session) }
    }

    /// Minutes an agent could take off her: duration × automatable × work.
    static func handoff(_ session: Session, _ label: Label) -> TimeInterval {
        session.duration * label.automatable * label.work
    }

    public static func tasks(sessions: [Session], labels: [Label], def: String) -> [TaskTime] {
        let answered = current(labels, def: def)
        let pairs = sessions.compactMap { session in answered[session.start].map { (session, $0) } }
        return Dictionary(grouping: pairs, by: { $0.1.task })
            .map { task, pairs in
                TaskTime(task: task, seconds: pairs.reduce(0) { $0 + $1.0.duration },
                         work: pairs.reduce(0) { $0 + $1.0.duration * $1.1.work },
                         handoff: pairs.reduce(0) { $0 + handoff($1.0, $1.1) })
            }
            .sorted { ($0.seconds, $1.task) > ($1.seconds, $0.task) }
    }

    /// Windows by time agents could take over, most first; each under the task that took most of its time.
    public static func candidates(sessions: [Session], labels: [Label], def: String) -> [Candidate] {
        let answered = current(labels, def: def)
        let pairs = sessions.compactMap { session in answered[session.start].map { (session, $0) } }
        return Dictionary(grouping: pairs, by: { "\($0.0.app ?? "Unknown")\u{1}\($0.0.windowTitle ?? "")" })
            .map { _, pairs in
                let task = Dictionary(grouping: pairs, by: { $0.1.task })
                    .max { ($0.value.reduce(0) { $0 + $1.0.duration }, $1.key) < ($1.value.reduce(0) { $0 + $1.0.duration }, $0.key) }!.key
                return Candidate(app: pairs[0].0.app ?? "Unknown", window: pairs[0].0.windowTitle ?? "", task: task,
                                 seconds: pairs.reduce(0) { $0 + $1.0.duration },
                                 handoff: pairs.reduce(0) { $0 + handoff($1.0, $1.1) }, sessions: pairs.count)
            }
            .sorted { ($0.handoff, $1.app, $1.window) > ($1.handoff, $0.app, $0.window) }
    }
}
