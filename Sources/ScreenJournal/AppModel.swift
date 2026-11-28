import AppKit
import JournalCore
import Observation

enum Preferences {
    static let interval = "captureInterval"
    static let retentionDays = "retentionDays"
    static let autoTidy = "autoTidyOldDays"
    static let excludedApps = "excludedBundleIDs"
    static let excludedKeywords = "excludedTitleKeywords"
    static let pausedUntil = "pausedUntil"
    static let onboarded = "onboarded"
    /// The Accessibility step came after the first release, so people who onboarded before it see it once.
    static let askedContext = "askedContext"
    static let language = "language"
    static let dictationKey = "dictationKey"
    static let dictationWords = "dictationWords"
    static let dictationLanguage = "dictationLanguage"
    static let dictationMicrophone = "dictationMicrophone"
    static let whatsappLast = "whatsappLast"
    static let awakeKeepDisplay = "awakeKeepDisplay"
    static let awakeLowPowerOnLidClose = "awakeLowPowerOnLidClose"
    static let awakeLowPowerFloor = "awakeLowPowerFloor"
    static let awakeEndFloor = "awakeEndFloor"
    static let awakeThermalRules = "awakeThermalRules"

    /// For AppKit, which reads it once when a window opens; SwiftUI views follow it live through `Localized`.
    static var currentLanguage: Language {
        UserDefaults.standard.string(forKey: language).flatMap(Language.init(rawValue:)) ?? .default
    }

    static var currentAwakeConfig: AwakeConfig {
        let d = UserDefaults.standard
        return AwakeConfig(
            keepDisplayAwake: d.bool(forKey: awakeKeepDisplay),
            lowPowerOnLidClose: d.object(forKey: awakeLowPowerOnLidClose) as? Bool ?? true,
            lowPowerFloor: d.object(forKey: awakeLowPowerFloor) as? Int ?? 40,
            endFloor: d.object(forKey: awakeEndFloor) as? Int ?? 10,
            thermalRules: d.object(forKey: awakeThermalRules) as? Bool ?? true
        )
    }

    static var currentDictationKey: DictationKey {
        UserDefaults.standard.string(forKey: dictationKey).flatMap(DictationKey.init(rawValue:)) ?? .rightCommand
    }

    static var currentDictationWords: [String] {
        UserDefaults.standard.stringArray(forKey: dictationWords) ?? []
    }

    static var currentDictationLanguage: DictationLanguage {
        UserDefaults.standard.string(forKey: dictationLanguage).flatMap(DictationLanguage.init(rawValue:)) ?? .default
    }

    /// Empty string / nil means Automatic (wired/built-in default, skipping Bluetooth).
    static var currentDictationMicrophone: String? {
        let uid = UserDefaults.standard.string(forKey: dictationMicrophone)
        return uid?.isEmpty == false ? uid : nil
    }

    static var currentExcludedApps: [String] {
        UserDefaults.standard.stringArray(forKey: excludedApps) ?? defaultExcludedApps
    }

    static var currentExcludedKeywords: [String] {
        UserDefaults.standard.stringArray(forKey: excludedKeywords) ?? []
    }

    static let intervalOptions: [TimeInterval] = [5, 10, 15, 30, 60]
    static let autoTidyKeepFullDays = 7

    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            interval: 10.0, retentionDays: 30, autoTidy: true,
            excludedApps: defaultExcludedApps, excludedKeywords: [String](),
            pausedUntil: 0.0, onboarded: false, askedContext: false,
            language: Language.default.rawValue, dictationKey: DictationKey.rightCommand.rawValue, dictationWords: [String](),
            dictationLanguage: DictationLanguage.default.rawValue, dictationMicrophone: "",
            awakeKeepDisplay: false, awakeLowPowerOnLidClose: true,
            awakeLowPowerFloor: 40, awakeEndFloor: 10, awakeThermalRules: true,
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
    private(set) var isSorting = false
    private(set) var lastSortError: String?
    private(set) var lastCaptureError: String?
    /// Incremented whenever labels or journal rows change from in-app actions, so open views reload.
    private(set) var journalRevision = 0

    let store = JournalStore.default
    let updater = Updater()
    private let worker: JournalWorker
    private let recorder: Recorder
    private var loop: Task<Void, Never>?
    private var isTicking = false
    private var lastSummary = Date.distantPast
    private var lastCatchUp = Date()
    private var lastSort = Date.distantPast
    /// Past days already fully sorted, so an hourly run reads only what can still change.
    private var settled: Set<SessionSorter.Settled> = []
    private var tallyDay = ""
    private var lastSized = Date.distantPast
    private var appSwitchToken: NSObjectProtocol?
    private let defaults = UserDefaults.standard
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        Preferences.registerDefaults()
        let worker = JournalWorker(store: store)
        self.worker = worker
        recorder = Recorder(store: store, worker: worker)
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
        if let appSwitchToken {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchToken)
            self.appSwitchToken = nil
        }
        recorder.closeAllSync(at: Date())
        try? store.append(EventRecord(at: Date(), kind: .stopped))
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

    /// Permanently removes the last `minutes` of capture (and any open frames), rebuilds summaries, and refreshes today's counters.
    @discardableResult
    func forgetRecent(minutes: Int) async -> Int {
        let now = Date()
        let from = now.addingTimeInterval(-Double(minutes) * 60)
        return await forget(from: from, to: now)
    }

    /// Permanently removes a local time range (e.g. a single session from `ScreensView`).
    @discardableResult
    func forget(from: Date, to: Date) async -> Int {
        await recorder.closeAll(at: Date())
        let removed = (try? await worker.forget(from: from, to: to)) ?? 0
        let today = store.day(of: Date())
        momentsToday = await worker.frameCount(day: today)
        bytesToday = await worker.size(day: today)
        settled.removeAll()
        journalRevision += 1
        return removed
    }

    /// Saves a manual label correction (`source: .agent`) for one session so it overrides the model's answer.
    func correctLabel(session: Session, work: Double, automatable: Double, task: String) async {
        guard case .success(let setup) = store.labelSetup() else { return }
        let day = store.day(of: session.start)
        let label = Label(session: session.start, work: work, automatable: automatable, task: task, def: setup.def, source: .agent)
        try? await worker.appendLabels([label], day: day)
        journalRevision += 1
    }

    /// Adds an app's bundle identifier to the excluded list if not already present.
    func excludeApp(bundleID: String) {
        var current = Preferences.currentExcludedApps
        guard !current.contains(bundleID) else { return }
        current.append(bundleID)
        defaults.set(current, forKey: Preferences.excludedApps)
    }

    /// Triggers background session sorting immediately (e.g. from "Your Week").
    func sortNow() {
        guard !isSorting else { return }
        guard let gateway = DecisionGateway.configured() else {
            lastSortError = Preferences.currentLanguage("Connect AI in Settings → General.")
            return
        }
        runSort(gateway: gateway)
    }

    /// Settings changed what the model is told: sort again in two minutes, once she's likely done editing.
    func sortAfterEdits() {
        settled.removeAll()
        lastSort = Date().addingTimeInterval(-3600 + 120)
    }

    /// Safe support summary for troubleshooting (no screen text, no API keys).
    func diagnosticsReport() async -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let total = ByteCountFormatter.string(fromByteCount: await worker.totalSize(), countStyle: .file)
        let todayBytes = ByteCountFormatter.string(fromByteCount: bytesToday, countStyle: .file)
        let days = store.dayNames().count
        let lines = [
            "Screen Journal \(version) (\(build))",
            "macOS: \(os)",
            "Status: \(status)",
            "Screen Recording: \(SystemAccess.hasScreenAccess ? "granted" : "missing")",
            "Accessibility: \(WindowContext.isTrusted ? "granted" : "missing")",
            "Microphone: \(Microphone.isAllowed ? "granted" : "missing")",
            "AI Gateway key: \(GatewayKey.isSaved ? "saved" : "not set")",
            "Capture interval: \(Int(defaults.double(forKey: Preferences.interval)))s | Retention: \(defaults.integer(forKey: Preferences.retentionDays))d | Auto-tidy: \(defaults.bool(forKey: Preferences.autoTidy))",
            "Excluded apps: \(Preferences.currentExcludedApps.count) | Excluded keywords: \(Preferences.currentExcludedKeywords.count)",
            "Journal: \(days) days, \(total) total (\(todayBytes) today, \(momentsToday) moments)",
            "Unsent dictations: \(UnsentRecordings.all().count)",
            lastCaptureError.map { "Last capture error: \($0)" },
            lastSortError.map { "Last sort error: \($0)" },
        ].compactMap { $0 }
        return lines.joined(separator: "\n")
    }

    private func clearPause() {
        pausedUntil = nil
        defaults.set(0.0, forKey: Preferences.pausedUntil)
    }

    private func tick() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }

        if let until = pausedUntil, until <= Date() { clearPause() }
        let isPaused = pausedUntil != nil
        let policy = CapturePolicy(
            excludedBundleIDs: Set(Preferences.currentExcludedApps),
            excludedTitleKeywords: Preferences.currentExcludedKeywords
        )
        switch await recorder.tick(policy: policy, isPaused: isPaused) {
        case .captured(let kept):
            lastCaptureError = nil
            tally(kept: kept)
            status = .recording
        case .skipped(.paused): status = .paused
        case .skipped: status = .resting
        case .noScreenAccess: status = .needsScreenAccess
        case .failed(let error):
            lastCaptureError = error.localizedDescription
            status = SystemAccess.hasScreenAccess ? .failing : .needsScreenAccess
        }
        housekeepIfDue()
    }

    /// Today's moments: rows already on disk at launch or day change, plus what this process has kept since.
    /// Disk size is re-measured every few minutes off the main actor, not on every menu open.
    private func tally(kept: Int) {
        let today = store.day(of: Date())
        let dayChanged = today != tallyDay
        if dayChanged {
            tallyDay = today
            lastSized = .distantPast
            Task { [worker] in
                let count = await worker.frameCount(day: today)
                self.momentsToday = count + kept
            }
        } else {
            momentsToday += kept
        }
        guard Date().timeIntervalSince(lastSized) > 300 else { return }
        lastSized = Date()
        Task { [worker] in
            self.bytesToday = await worker.size(day: today)
        }
    }

    /// Today's summary every 15 minutes; the launch catch-up and sorting hourly.
    private func housekeepIfDue() {
        sortIfDue()
        if Date().timeIntervalSince(lastSummary) > 15 * 60 {
            lastSummary = Date()
            let today = store.day(of: Date())
            Task { [worker] in await worker.summarize(day: today) }
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
        runSort(gateway: gateway)
    }

    private func runSort(gateway: DecisionGateway) {
        lastSort = Date()
        isSorting = true
        lastSortError = nil
        let sorter = SessionSorter(store: store)
        let settled = settled
        Task {
            switch await sorter.sortRecent(gateway: gateway, now: Date(), skipping: settled) {
            case .success(let outcome):
                self.settled.formUnion(outcome.settled)
                if let first = outcome.failures.first {
                    self.lastSortError = friendlySortError(first)
                }
                if outcome.sorted > 0 {
                    self.journalRevision += 1
                }
            case .failure(let error):
                self.lastSortError = error.localizedDescription
            }
            self.isSorting = false
        }
    }

    private func friendlySortError(_ message: String) -> String {
        let language = Preferences.currentLanguage
        if message.hasPrefix("401") || message.hasPrefix("403") {
            return language("The gateway refused the AI key.")
        }
        if message.hasPrefix("No reply.") {
            return language("No internet connection.")
        }
        return message
    }

    /// Summarizes days missed while the Mac was off, slims old screenshots if enabled, and applies retention.
    private func catchUp() {
        let today = store.day(of: Date())
        let retention = max(1, defaults.integer(forKey: Preferences.retentionDays))
        let autoTidyDays = defaults.bool(forKey: Preferences.autoTidy) ? Preferences.autoTidyKeepFullDays : nil
        Task { [worker] in
            await worker.catchUp(today: today, retentionDays: retention, autoTidyDays: autoTidyDays)
        }
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
