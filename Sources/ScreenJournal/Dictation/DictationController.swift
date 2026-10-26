import AppKit
import JournalCore
import Observation
import os

/// Tap the dictation key, speak, tap again: what she said is typed where her cursor is, tidied.
/// With text highlighted when she starts, what she says is how to rewrite it.
/// Audio and text stay in memory and are gone once pasted; nothing reaches the journal.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case listening
        case working
        /// One line for a moment, then gone.
        case notice(String)
    }

    /// Longer recordings stop on their own, so a forgotten tap doesn't record all afternoon.
    static let longest: TimeInterval = 5 * 60
    /// Shorter is a slip of the finger: nothing is sent.
    static let shortest: TimeInterval = 0.4
    private static let log = Logger(subsystem: "com.filippofantozzi.ScreenJournal", category: "dictation")

    private(set) var phase: Phase = .idle
    /// Whether the highlighted text will be rewritten; known a moment after listening starts.
    private(set) var isEditing = false
    /// Listening, but no sound has arrived yet, as from a slow default input on a Mac without its own microphone.
    private(set) var isConnecting = false
    /// The last loudness readings, oldest first, for the pill's bars.
    private(set) var levels: [Float] = Array(repeating: 0, count: 9)

    @ObservationIgnored private var watcher: KeyWatcher?
    @ObservationIgnored private var waitForTrust: Task<Void, Never>?
    @ObservationIgnored private let microphone = Microphone()
    @ObservationIgnored private var selection: Task<String?, Never>?
    @ObservationIgnored private var limit: Task<Void, Never>?
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
        watcher = KeyWatcher(key: key, onTap: { [weak self] in self?.toggle() }, onEscape: { [weak self] in self?.cancel() })
    }

    private func toggle() {
        switch phase {
        case .idle, .notice: Task { await start() }
        case .listening: Task { await finish() }
        case .working: break
        }
    }

    /// Recording starts at once, so the first words aren't lost; the selection is read meanwhile.
    private func start() async {
        guard SpeechGateway.configured() != nil else { return notice(language("Connect AI in Settings → General.")) }
        if !Microphone.wasAsked { _ = await Microphone.requestAccess() }
        guard Microphone.isAllowed else { return notice(language("Allow the microphone in Settings → Dictation.")) }
        let started = microphone.start(from: AudioInputs.builtIn()) { [weak self] level in
            Task { @MainActor in self?.hear(level) }
        }
        if case .failure = started { return notice(language("No microphone.")) }
        clearNotice?.cancel()
        isEditing = false
        isConnecting = true
        levels = levels.map { _ in 0 }
        phase = .listening
        listeningSince = Date()
        pill.show()
        let selection = Task { await Selection.read() }
        self.selection = selection
        limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.longest))
            if !Task.isCancelled { await self?.finish() }
        }
        isEditing = DictationIntent(selection: await selection.value) != .write
    }

    private func finish() async {
        guard phase == .listening else { return }
        phase = .working
        limit?.cancel()
        let (wav, seconds, silent) = microphone.stop()
        let intent = DictationIntent(selection: await selection?.value)
        // A short tap is a slip; a long one that recorded nothing means no sound arrived, which she should hear about.
        guard Date().timeIntervalSince(listeningSince) >= Self.shortest else { return hide() }
        guard !silent, seconds >= Self.shortest else { return notice(language("Didn't hear anything. Check the microphone in Settings → Dictation.")) }
        guard let gateway = SpeechGateway.configured() else { return notice(language("Connect AI in Settings → General.")) }
        let words = Preferences.currentDictationWords
        let transcript: String
        switch await gateway.transcribe(wav: wav, words: words, language: Preferences.currentDictationLanguage) {
        case .success(let text) where !text.isEmpty: transcript = text
        case .success:
            Self.log.notice("transcript empty")
            return notice(language("Didn't catch that."))
        case .failure(let error):
            Self.log.error("transcription failed: \(error.message, privacy: .public)")
            return notice(reason(error))
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
        switch await Paster.paste(text) {
        case .pasted:
            Self.log.info("pasted")
            hide()
        case .copied:
            Self.log.notice("no text field focused; left on the clipboard")
            notice(language("Copied: press ⌘V to paste."))
        }
    }

    /// Esc while listening drops the recording; nothing is sent.
    func cancel() {
        guard phase == .listening else { return }
        limit?.cancel()
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

    private func notice(_ message: String) {
        phase = .notice(message)
        pill.show()
        clearNotice?.cancel()
        clearNotice = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
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
        if error.message == "No reply." { return language("No internet connection.") }
        return language("Couldn't transcribe. Try again.")
    }
}
