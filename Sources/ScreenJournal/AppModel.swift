import AppKit
import JournalCore
import Observation

enum Preferences {
    static let interval = "captureInterval"
    static let retentionDays = "retentionDays"
    static let excludedApps = "excludedBundleIDs"
    static let pausedUntil = "pausedUntil"
    static let onboarded = "onboarded"
    /// The Accessibility step came after the first release, so people who onboarded before it see it once.
    static let askedContext = "askedContext"
    static let language = "language"

    /// For AppKit, which reads it once when a window opens; SwiftUI views follow it live through `Localized`.
    static var currentLanguage: Language {
        UserDefaults.standard.string(forKey: language).flatMap(Language.init(rawValue:)) ?? .default
    }

    static let intervalOptions: [TimeInterval] = [5, 10, 15, 30, 60]

    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            interval: 10.0, retentionDays: 30, excludedApps: defaultExcludedApps, pausedUntil: 0.0, onboarded: false, askedContext: false,
            language: Language.default.rawValue,
        ])
    }
}

/// What was on screen when she asked to note it.
struct Moment {
    let app: String?
    let bundleID: String?
    let windowTitle: String?
    let frameID: String?
}

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case starting, recording, paused, resting, needsScreenAccess, failing
    }

    private(set) var status: Status = .starting
    private(set) var pausedUntil: Date?
    private(set) var momentsToday = 0
    private(set) var bytesToday: Int64 = 0

    let store = JournalStore.default
    let updater = Updater()
    private let recorder: Recorder
    private var loop: Task<Void, Never>?
    private var lastSummary = Date.distantPast
    private var lastCatchUp = Date()
    private var lastSort = Date.distantPast
    private var isSorting = false
    private var tallyDay = ""
    private var lastSized = Date.distantPast
    private var appSwitchToken: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        Preferences.registerDefaults()
        recorder = Recorder(store: store)
        let stored = defaults.double(forKey: Preferences.pausedUntil)
        pausedUntil = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    var isOnboarded: Bool { defaults.bool(forKey: Preferences.onboarded) }

    func markOnboarded() {
        defaults.set(true, forKey: Preferences.onboarded)
        defaults.set(true, forKey: Preferences.askedContext)
        start()
    }

    /// Onboarded before the Accessibility step existed, and never asked since.
    var shouldAskForContext: Bool {
        !defaults.bool(forKey: Preferences.askedContext) && !WindowContext.isTrusted
    }

    func markAskedForContext() {
        defaults.set(true, forKey: Preferences.askedContext)
    }

    func start() {
        guard loop == nil else { return }
        try? store.installGuide()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        recorder.record(EventRecord(at: Date(), kind: .started, version: version))
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

    /// Read before the note window opens and takes focus.
    func currentMoment() -> Moment {
        let front = ActivityReader.frontmost
        let frame = recorder.focusedFrame
        let frontIsHers = front.map {
            !SystemApps.isIgnored(app: $0.localizedName, bundleID: $0.bundleIdentifier, ownBundleID: ownBundleID)
        } ?? false
        return Moment(
            app: frontIsHers ? front?.localizedName : frame?.app,
            bundleID: frontIsHers ? front?.bundleIdentifier : frame?.bundleID,
            windowTitle: frame?.windowTitle,
            frameID: frame?.id
        )
    }

    func addNote(_ text: String, about moment: Moment) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recorder.record(EventRecord(
            at: Date(), kind: .note, app: moment.app, bundleID: moment.bundleID,
            windowTitle: moment.windowTitle, frameID: moment.frameID, text: trimmed
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
            tally(kept: kept)
            status = .recording
        case .skipped(.paused): status = .paused
        case .skipped: status = .resting
        case .noScreenAccess: status = .needsScreenAccess
        case .failed: status = SystemAccess.hasScreenAccess ? .failing : .needsScreenAccess
        }
        housekeepIfDue()
    }

    /// Today's moments: rows already on disk at launch or day change, plus what this process has kept since.
    /// Disk size is re-measured every few minutes, not on every menu open.
    private func tally(kept: Int) {
        let today = store.day(of: Date())
        if today != tallyDay {
            tallyDay = today
            momentsToday = store.frameCount(day: today)
            lastSized = .distantPast
        }
        momentsToday += kept
        guard Date().timeIntervalSince(lastSized) > 300 else { return }
        lastSized = Date()
        bytesToday = store.size(day: today)
    }

    /// Today's summary every 15 minutes; the launch catch-up and sorting hourly.
    private func housekeepIfDue() {
        sortIfDue()
        if Date().timeIntervalSince(lastSummary) > 15 * 60 {
            lastSummary = Date()
            try? store.summarize(day: store.day(of: Date()))
        }
        if Date().timeIntervalSince(lastCatchUp) > 3600 {
            lastCatchUp = Date()
            catchUp()
        }
    }

    /// Sorts the recent week's finished sessions, on the first tick and then hourly, once a key is saved.
    /// What fails stays unsorted and is asked again next time.
    private func sortIfDue() {
        guard !isSorting, Date().timeIntervalSince(lastSort) > 3600, let gateway = DecisionGateway.configured() else { return }
        lastSort = Date()
        isSorting = true
        let sorter = SessionSorter(store: store)
        Task {
            _ = await sorter.sortRecent(gateway: gateway, now: Date())
            isSorting = false
        }
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
                guard let self, !SystemApps.isIgnored(app: app?.localizedName, bundleID: app?.bundleIdentifier, ownBundleID: self.ownBundleID)
                else { return }
                self.recorder.record(EventRecord(at: Date(), kind: .appSwitch, app: app?.localizedName, bundleID: app?.bundleIdentifier))
            }
        }
    }
}
