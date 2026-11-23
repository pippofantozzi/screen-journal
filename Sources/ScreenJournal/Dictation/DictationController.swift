import AppKit
import JournalCore
import Observation
import os

/// Tap the dictation key, speak, tap again: what she said is typed where her cursor is, tidied.
/// With text highlighted when she starts, what she says is how to rewrite it. Double-tap, or the pill's buttons, pause it; Esc drops it.
/// A dictation's recording stays on disk until its text is pasted, so she can retry it after a failure; nothing reaches the journal.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening
        /// Listening held: nothing is recorded until she taps the key again.
        case paused
        case working
        /// One line for a moment, then gone.
        case notice(String)
    }

    /// Longer recordings stop on their own, so a forgotten tap doesn't record all afternoon.
    static let longest: TimeInterval = 15 * 60
    /// Warning window before the automatic stop.
    static let warningLead: TimeInterval = 30
    /// Longer recordings go to the transcriber as pieces this long, all at once, so none is too big to send.
    static let piece: TimeInterval = 3 * 60
    /// Shorter is a slip of the finger: nothing is sent.
    static let shortest: TimeInterval = 0.4
    private static let recentLimit = 5
    private static let log = Logger(subsystem: "com.filippofantozzi.ScreenJournal", category: "dictation")

    private(set) var phase: Phase = .idle
    /// Whether the highlighted text will be rewritten; known a moment after listening starts.
    private(set) var isEditing = false
    /// Listening, but no sound has arrived yet, as from a slow default input on a Mac without its own microphone.
    private(set) var isConnecting = false
    /// Recorded seconds so far (excluding pauses), for the pill's timer.
    private(set) var elapsedSeconds: TimeInterval = 0
    /// The last loudness readings, oldest first, for the pill's bars.
    private(set) var levels: [Float] = Array(repeating: 0, count: 9)
    /// Number of recordings waiting on disk after a failure.
    private(set) var unsentCount = UnsentRecordings.all().count
    /// Last few delivered dictations (newest first), in memory only, so a lost paste can always be copied again.
    private(set) var recent: [String] = []

    var hasUnsent: Bool { unsentCount > 0 }
    var isNearLimit: Bool { elapsedSeconds >= Self.longest - Self.warningLead }

    @ObservationIgnored private var watcher: KeyWatcher?
    @ObservationIgnored private var waitForTrust: Task<Void, Never>?
    @ObservationIgnored private let microphone = Microphone()
    @ObservationIgnored private var selection: Task<String?, Never>?
    @ObservationIgnored private var limit: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var clearNotice: Task<Void, Never>?
    @ObservationIgnored private var listeningSince = Date.distantPast
    @ObservationIgnored private lazy var pill = DictationPillPanel(controller: self)

    /// Watches for the chosen key, or stops watching. Without the Accessibility grant, waits for it and starts then.
    func use(_ key: DictationKey) {
        watcher = nil
        waitForTrust?.cancel()
        guard key != .off else { return cancel() }
        guard WindowContext.isTrusted else {
            waitForTrust = Task { [weak self] in
                while !Task.isCancelled, !WindowContext.isTrusted { try? await Task.sleep(for: .seconds(2)) }
                if !Task.isCancelled { self?.use(key) }
            }
            return
        }
        // Only wait for a double-tap while recording (to pause); starting from idle fires immediately with zero delay.
        watcher = KeyWatcher(
            key: key,
            shouldWaitForDoubleTap: { [weak self] in self?.isRecording == true },
            onTap: { [weak self] in self?.toggle() },
            onDoubleTap: { [weak self] in self?.togglePause() },
            onEscape: { [weak self] in self?.cancel() }
        )
    }

    private func toggle() {
        switch phase {
        case .idle, .notice: Task { await start() }
        case .listening: Task { await finish() }
        case .paused: resume()
        case .working: break
        }
    }

    var isRecording: Bool { phase == .listening || phase == .paused }

    func togglePause() {
        switch phase {
        case .listening: pause()
        case .paused: resume()
        case .idle, .working, .notice: break
        }
    }

    private func pause() {
        limit?.cancel()
        clock?.cancel()
        microphone.pause()
        elapsedSeconds = microphone.seconds
        phase = .paused
    }

    private func resume() {
        microphone.resume()
        phase = .listening
        stop(after: max(1, Self.longest - microphone.seconds))
        startClock()
        Sounds.play(.start)
    }

    /// Paused time doesn't count toward the limit.
    private func stop(after seconds: TimeInterval) {
        limit?.cancel()
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { await self?.finish() }
        }
    }

    private func startClock() {
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled, let self, self.phase == .listening {
                self.elapsedSeconds = self.microphone.seconds
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Recording starts at once, so the first words aren't lost; the selection is read meanwhile.
    private func start() async {
        guard SpeechGateway.configured() != nil else { return notice(language("Connect AI in Settings → General.")) }
        if !Microphone.wasAsked { _ = await Microphone.requestAccess() }
        guard Microphone.isAllowed else { return notice(language("Allow the microphone in Settings → Dictation.")) }
        let inputID = AudioInputs.preferred(savedUID: Preferences.currentDictationMicrophone)
        let started = microphone.start(from: inputID) { [weak self] level in
            Task { @MainActor in self?.hear(level) }
        }
        if case .failure = started { return notice(language("No microphone.")) }
        clearNotice?.cancel()
        isEditing = false
        isConnecting = true
        elapsedSeconds = 0
        levels = levels.map { _ in 0 }
        phase = .listening
        listeningSince = Date()
        pill.show()
        Sounds.play(.start)
        let selection = Task { await Selection.read() }
        self.selection = selection
        stop(after: Self.longest)
        startClock()
        isEditing = DictationIntent(selection: await selection.value) != .write
    }

    private func finish() async {
        guard isRecording else { return }
        let targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        phase = .working
        limit?.cancel()
        clock?.cancel()
        let (wav, seconds, silent) = microphone.stop()
        let intent = DictationIntent(selection: await selection?.value)
        // A short tap is a slip; a long one that recorded nothing means no sound arrived, which she should hear about.
        guard Date().timeIntervalSince(listeningSince) >= Self.shortest else { return hide() }
        guard !silent, seconds >= Self.shortest else { return notice(language("Didn't hear anything. Check the microphone in Settings → Dictation.")) }
        // An instruction for an edit is quick to say again; a dictation may be minutes of speech.
        let saved = intent == .write ? UnsentRecordings.keep(wav) : nil
        refreshUnsent()
        guard let gateway = SpeechGateway.configured() else { return notice(language("Connect AI in Settings → General.")) }
        await deliver(wav, intent: intent, saved: saved, targetBundleID: targetBundleID, through: gateway)
    }

    /// The newest unsent recording, typed where her cursor is now, as a dictation.
    func retry() {
        switch phase {
        case .listening, .paused, .working: return
        case .idle, .notice: break
        }
        guard let saved = UnsentRecordings.all().first, let wav = try? Data(contentsOf: saved) else { return }
        guard let gateway = SpeechGateway.configured() else { return notice(language("Connect AI in Settings → General.")) }
        let targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        clearNotice?.cancel()
        isEditing = false
        phase = .working
        pill.show()
        Task { await deliver(wav, intent: .write, saved: saved, targetBundleID: targetBundleID, through: gateway) }
    }

    func discardLastUnsent() {
        UnsentRecordings.discardNewest()
        refreshUnsent()
    }

    func copyRecent(_ text: String) {
        Clipboard.write(text)
    }

    /// Transcribed, rewritten and pasted; the saved recording goes once its text is pasted, or when it held no speech.
    private func deliver(_ wav: Data, intent: DictationIntent, saved: URL?, targetBundleID: String?, through gateway: SpeechGateway) async {
        Sounds.play(.working)
        let words = Preferences.currentDictationWords
        let transcript: String
        switch await transcribe(wav, saved: saved, words: words, through: gateway) {
        case .success(let text) where !text.isEmpty: transcript = text
        case .success:
            Self.log.notice("transcript empty")
            discard(saved)
            return notice(language("Didn't catch that."))
        case .failure(let error):
            Self.log.error("transcription failed: \(error.message, privacy: .public)")
            guard saved != nil else { return notice(reason(error)) }
            return notice(reason(error) + " " + language("Retry from the menu bar."), for: 6)
        }
        let text: String
        switch await gateway.rewrite(intent, transcript: transcript, words: words) {
        case .success(let rewritten) where !rewritten.isEmpty: text = rewritten
        // What she said is still worth typing as heard; an edit without its rewrite is not.
        case _ where intent == .write: text = transcript
        case .success: return notice(language("Didn't catch that."))
        case .failure(let error):
            Self.log.error("rewrite failed: \(error.message, privacy: .public)")
            return notice(reason(error))
        }
        rememberRecent(text)
        discard(saved)
        Sounds.play(.done)
        // If focus moved to another app while waiting, copy to the clipboard rather than pasting blindly.
        let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let targetBundleID, currentBundleID != targetBundleID {
            Clipboard.write(text)
            Self.log.info("copied (focus moved)")
            notice(language("Copied — press ⌘V."), for: 3.5)
        } else {
            Paster.paste(text)
            Self.log.info("pasted")
            hide()
        }
    }

    /// Each piece's text, in order; successful pieces are cached beside the saved recording so retries only re-send failed ones.
    private func transcribe(_ wav: Data, saved: URL?, words: [String], through gateway: SpeechGateway) async -> Result<String, LabelError> {
        let pieces = RecordingPieces.split(WAV.samples(of: wav), sampleRate: Microphone.sampleRate, longest: Self.piece)
        let spoken = Preferences.currentDictationLanguage
        var cached = saved.map(UnsentRecordings.chunks(for:)) ?? [:]
        let missing = pieces.indices.filter { cached[$0] == nil }
        let results = await withTaskGroup(of: (Int, Result<String, LabelError>).self) { group in
            for index in missing {
                let audio = WAV.encode(samples: pieces[index], sampleRate: Microphone.sampleRate)
                group.addTask { (index, await gateway.transcribe(audio, words: words, language: spoken)) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        var firstError: LabelError?
        for (index, result) in results {
            switch result {
            case .success(let text): cached[index] = text
            case .failure(let error): if firstError == nil { firstError = error }
            }
        }
        if let saved, !cached.isEmpty { UnsentRecordings.saveChunks(cached, for: saved) }
        if let firstError { return .failure(firstError) }
        let texts = pieces.indices.compactMap { cached[$0] }.filter { !$0.isEmpty }
        return .success(texts.joined(separator: " "))
    }

    private func rememberRecent(_ text: String) {
        recent.removeAll { $0 == text }
        recent.insert(text, at: 0)
        if recent.count > Self.recentLimit { recent = Array(recent.prefix(Self.recentLimit)) }
    }

    private func discard(_ saved: URL?) {
        if let saved { UnsentRecordings.discard(saved) }
        refreshUnsent()
    }

    private func refreshUnsent() {
        unsentCount = UnsentRecordings.all().count
    }

    /// Drops the recording, paused or not; nothing is sent or kept.
    func cancel() {
        guard isRecording else { return }
        limit?.cancel()
        clock?.cancel()
        selection?.cancel()
        _ = microphone.stop()
        hide()
    }

    private func hear(_ level: Float) {
        guard phase == .listening else { return }
        isConnecting = false
        // Rises at once, falls over a few readings, so words read as pulses rather than flicker.
        let last = levels.last ?? 0
        levels = Array(levels.dropFirst()) + [level >= last ? level : last * 0.55 + level * 0.45]
    }

    private func notice(_ message: String, for seconds: Double = 2.5) {
        phase = .notice(message)
        pill.show()
        clearNotice?.cancel()
        clearNotice = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.hide() }
        }
    }

    /// Read when a message shows, so it follows the language she picked.
    private var language: Language { Preferences.currentLanguage }

    private func hide() {
        phase = .idle
        pill.hide()
    }

    private func reason(_ error: LabelError) -> String {
        if error.message.hasPrefix("401") || error.message.hasPrefix("403") { return language("The gateway refused the AI key.") }
        if error.message.hasPrefix("No reply.") { return language("No internet connection.") }
        return language("Couldn't transcribe. Try again.")
    }
}
