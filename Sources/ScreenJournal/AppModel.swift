import AppKit
import JournalCore
import Observation

enum Preferences {
    static let interval = "captureInterval"
    static let retentionDays = "retentionDays"
    static let excludedApps = "excludedBundleIDs"
    static let pausedUntil = "pausedUntil"
    static let onboarded = "onboarded"

    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            interval: 10.0, retentionDays: 30, excludedApps: defaultExcludedApps, pausedUntil: 0.0, onboarded: false,
        ])
    }
}

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case starting, recording, paused, resting, needsScreenAccess, failing
    }

    private(set) var status: Status = .starting
    private(set) var pausedUntil: Date?
    private(set) var framesKept = 0

    let store = JournalStore.default
    let updater = Updater()
    private let recorder: Recorder
    private var loop: Task<Void, Never>?
    private var lastSummary = Date()
    private var appSwitchToken: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    init() {
        Preferences.registerDefaults()
        recorder = Recorder(store: store)
        let stored = defaults.double(forKey: Preferences.pausedUntil)
        pausedUntil = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    var isOnboarded: Bool { defaults.bool(forKey: Preferences.onboarded) }

    func markOnboarded() {
        defaults.set(true, forKey: Preferences.onboarded)
        start()
    }

    func start() {
        guard loop == nil else { return }
        try? store.installGuide()
        recorder.record(EventRecord(at: Date(), kind: .started))
        observeAppSwitches()
        catchUp()
        loop = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.tick()
                try? await Task.sleep(for: .seconds(max(2, self.defaults.double(forKey: Preferences.interval))))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        recorder.closeAll(at: Date())
        recorder.record(EventRecord(at: Date(), kind: .stopped))
        try? store.summarize(day: store.day(of: Date()))
    }

    /// `nil` duration pauses until resumed.
    func pause(for duration: TimeInterval?) {
        let until = duration.map { Date().addingTimeInterval($0) } ?? .distantFuture
        pausedUntil = until
        defaults.set(until.timeIntervalSince1970, forKey: Preferences.pausedUntil)
        status = .paused
    }

    func resume() {
        clearPause()
        Task { await tick() }
    }

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recorder.record(EventRecord(
            at: Date(), kind: .note, app: ActivityReader.frontmost?.localizedName,
            bundleID: ActivityReader.frontmost?.bundleIdentifier, text: trimmed
        ))
    }

    func openFolder() {
        NSWorkspace.shared.open(store.root)
    }

    private func clearPause() {
        pausedUntil = nil
        defaults.set(0.0, forKey: Preferences.pausedUntil)
    }

    private func tick() async {
        if let until = pausedUntil, until <= Date() { clearPause() }
        let isPaused = pausedUntil != nil
        let policy = CapturePolicy(excludedBundleIDs: Set(defaults.stringArray(forKey: Preferences.excludedApps) ?? []))
        switch await recorder.tick(policy: policy, isPaused: isPaused) {
        case .captured(let kept):
            framesKept += kept
            status = .recording
        case .skipped(.paused): status = .paused
        case .skipped: status = .resting
        case .noScreenAccess: status = .needsScreenAccess
        case .failed: status = SystemAccess.hasScreenAccess ? .failing : .needsScreenAccess
        }
        housekeepIfDue()
    }

    /// Hourly: refresh today's summary, then the same catch-up as launch.
    private func housekeepIfDue() {
        guard Date().timeIntervalSince(lastSummary) > 3600 else { return }
        lastSummary = Date()
        try? store.summarize(day: store.day(of: Date()))
        catchUp()
    }

    /// Summarizes days missed while the Mac was off, and applies retention.
    private func catchUp() {
        let today = store.day(of: Date())
        for day in store.unsummarizedDays(before: today) { try? store.summarize(day: day) }
        try? store.purge(keepDays: max(1, defaults.integer(forKey: Preferences.retentionDays)), today: today)
    }

    private func observeAppSwitches() {
        appSwitchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.recorder.record(EventRecord(at: Date(), kind: .appSwitch, app: app?.localizedName, bundleID: app?.bundleIdentifier))
            }
        }
    }
}
