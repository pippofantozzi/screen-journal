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
        let failedDays: Set<String>
        /// Past days now fully sorted, for the next run to skip.
        var settled: Set<Settled> = []
    }

    /// A past day sorted without failures under one setup: nothing new lands in it, so it needn't be read again.
    struct Settled: Hashable, Sendable {
        let day: String
        let def: String
    }

    /// Covers Your Week and then some.
    static let recentDays = 8

    /// The recent days' pending sessions, asked and kept, skipping days already settled under this setup.
    func sortRecent(gateway: DecisionGateway, now: Date, skipping settled: Set<Settled>) async -> Result<Outcome, Error> {
        do {
            let setup = try store.labelSetup().get()
            let days = store.dayNames().sorted().suffix(Self.recentDays).filter { !settled.contains(Settled(day: $0, def: setup.def)) }
            let asks = try await pending(days, setup: setup, now: now)
            return await sort(asks, setup: setup, gateway: gateway).map { outcome in
                // A session can still be going until five minutes after midnight.
                let past = store.day(of: now.addingTimeInterval(-Labeling.quiet))
                var outcome = outcome
                outcome.settled = Set(days.filter { $0 < past && !outcome.failedDays.contains($0) }.map { Settled(day: $0, def: setup.def) })
                return outcome
            }
        } catch {
            return .failure(error)
        }
    }

    /// Each day read and parsed in parallel.
    private func pending(_ days: [String], setup: LabelSetup, now: Date) async throws -> [Ask] {
        try await withThrowingTaskGroup(of: [Ask].self) { group in
            for day in days { group.addTask { try pending(day, setup: setup, titlesOnly: false, now: now) } }
            return try await group.reduce(into: []) { $0 += $1 }
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
        var failures: [String] = [], failedDays: Set<String> = []
        do {
            for day in Set(asks.map(\.day)) {
                let labels = results.filter { $0.ask.day == day }.compactMap { result -> Label? in
                    switch result.answers {
                    case .success(let a):
                        return Label(session: result.ask.session.start, work: a.work, automatable: a.automatable, task: a.task,
                                     def: setup.def, source: result.source)
                    case .failure(let error):
                        failures.append(error.message)
                        failedDays.insert(day)
                        return nil
                    }
                }
                try store.append(labels, day: day)
            }
        } catch {
            return .failure(error)
        }
        return .success(Outcome(sorted: asks.count - failures.count, failures: failures, failedDays: failedDays))
    }

    private struct Answered: Sendable {
        let ask: Ask
        let source: Label.Source
        let answers: Result<SystemOne.Answers, LabelError>
    }

    /// Sixteen requests in flight: each answers one session in about a second.
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
            for _ in 0..<16 { start() }
            for await result in group {
                results.append(result)
                start()
            }
            return results
        }
    }
}
