import Foundation
import JournalCore

/// Asks the models about sessions her current setup hasn't answered, and keeps the answers.
/// The app runs it every hour on the last week; `label --apply` runs it on demand.
struct SessionSorter: Sendable {
    let store: JournalStore

    /// One session to ask about, with what the model will see.
    struct Ask: Sendable {
        let day: String
        let session: Session
        let state: SessionState
        /// Sent along, to the vision model, when she allows it and nothing on screen was redacted.
        let screenshot: URL?
    }

    struct Outcome: Sendable {
        let sorted: Int
        /// One message per session that failed; those stay pending for the next run.
        let failures: [String]
    }

    /// Covers Your Week and then some, while an hourly run stays a few megabytes of reading.
    static let recentDays = 8

    /// The recent days' pending sessions, asked and kept.
    func sortRecent(gateway: DecisionGateway, now: Date) async -> Result<Outcome, Error> {
        do {
            let setup = try store.labelSetup().get()
            let days = store.dayNames().sorted().suffix(Self.recentDays)
            let asks = try days.flatMap { try pending($0, setup: setup, titlesOnly: false, now: now) }
            return await sort(asks, setup: setup, gateway: gateway)
        } catch {
            return .failure(error)
        }
    }

    /// Unlabelled finished sessions, plus, when she allows screenshots, text-only ones the screenshot would tell more about.
    func pending(_ day: String, setup: LabelSetup, titlesOnly: Bool, now: Date) throws -> [Ask] {
        let rows = try store.rows(day: day), labels = try store.labels(day: day)
        let sessions = rows.sessions
        let finished = Set(Labeling.finished(sessions, at: now).map(\.start))
        let unlabelled = Set(Labeling.pending(sessions: sessions, labels: labels, def: setup.def).map(\.start)).intersection(finished)
        let unseen = setup.screenshots && !titlesOnly
            ? Set(Labeling.unseen(sessions: sessions, labels: labels, def: setup.def).map(\.start)).intersection(finished) : []
        return sessions.enumerated().compactMap { i, session in
            guard unlabelled.contains(session.start) || unseen.contains(session.start) else { return nil }
            let state = Self.state(at: i, of: sessions, frames: rows.frames, setup: setup, textLimit: titlesOnly ? 0 : 600)
            let image = store.screenshot(of: session)
            let look = unseen.contains(session.start) && Labeling.wantsLook(state) && FileManager.default.fileExists(atPath: image.path)
            guard look || unlabelled.contains(session.start) else { return nil }
            return Ask(day: day, session: session, state: state, screenshot: look ? image : nil)
        }
    }

    /// What the model sees of one session: its own text, and the windows either side.
    static func state(at i: Int, of sessions: [Session], frames: [FrameRecord], setup: LabelSetup, textLimit: Int) -> SessionState {
        SessionState(sessions[i], before: i > 0 ? sessions[i - 1] : nil, after: i + 1 < sessions.count ? sessions[i + 1] : nil,
                     about: setup.about, frames: frames, textLimit: textLimit)
    }

    /// Asks, then appends each day's answers to it.
    func sort(_ asks: [Ask], setup: LabelSetup, gateway: DecisionGateway) async -> Result<Outcome, Error> {
        let results = await Self.ask(asks, kinds: setup.kinds, gateway: gateway)
        var failures: [String] = []
        do {
            for day in Set(asks.map(\.day)) {
                let labels = results.filter { $0.ask.day == day }.compactMap { result -> Label? in
                    switch result.answers {
                    case .success(let a):
                        return Label(session: result.ask.session.start, work: a.work, automatable: a.automatable, task: a.task,
                                     def: setup.def, source: result.source)
                    case .failure(let error):
                        failures.append(error.message)
                        return nil
                    }
                }
                try store.append(labels, day: day)
            }
        } catch {
            return .failure(error)
        }
        return .success(Outcome(sorted: asks.count - failures.count, failures: failures))
    }

    private struct Answered: Sendable {
        let ask: Ask
        let source: Label.Source
        let answers: Result<SystemOne.Answers, LabelError>
    }

    /// Eight requests in flight: each answers one session in about a second.
    private static func ask(_ asks: [Ask], kinds: [TaskKind], gateway: DecisionGateway) async -> [Answered] {
        await withTaskGroup(of: Answered.self) { group in
            var results: [Answered] = []
            var next = asks.makeIterator()
            func start() {
                guard let ask = next.next() else { return }
                group.addTask {
                    let screenshot = ask.screenshot.flatMap { ImageCodec.jpeg(at: $0) }
                    return Answered(ask: ask, source: screenshot == nil ? .model : .look,
                                    answers: await gateway.answers(ask.state, kinds: kinds, screenshot: screenshot))
                }
            }
            for _ in 0..<8 { start() }
            for await result in group {
                results.append(result)
                start()
            }
            return results
        }
    }
}
