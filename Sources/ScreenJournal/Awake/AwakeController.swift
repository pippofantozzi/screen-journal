import AppKit
import Foundation
import JournalCore
import Observation

/// Owns timed Keep Awake sessions: IOKit assertions, optional closed-lid `pmset disablesleep`,
/// crash-safe recovery journal + launchd backstop, battery/thermal safety floors, and CLI IPC.
@MainActor
@Observable
final class AwakeController {
    private(set) var session: AwakeSession?
    private(set) var journal: AwakeJournal = AwakeJournal()
    private(set) var countdownText: String = ""
    private(set) var closedLidProtected: Bool = false
    private(set) var sudoersReady: Bool = false
    private(set) var lastError: String?

    var isActive: Bool { session != nil }

    private let assertions = IOPMAssertionGuard()
    private var monitorTask: Task<Void, Never>?
    private var thermalObserver: NSObjectProtocol?
    private var ipcObserver: NSObjectProtocol?
    private var wasHot = false
    private var tickCount = 0

    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? AwakeIPC.defaultBundleID }

    func start() {
        startIPCListener()
        Task {
            let ready = await Task.detached(priority: .utility) { PmsetBridge.isPasswordlessSudoAvailable() }.value
            self.sudoersReady = ready
            await self.reconcileOnLaunch()
        }
    }

    func recheckSudoers() {
        Task {
            let ready = await Task.detached(priority: .utility) { PmsetBridge.isPasswordlessSudoAvailable() }.value
            self.sudoersReady = ready
            self.writeStatus()
        }
    }

    /// Synchronous cleanup on app quit so Screen Journal never exits leaving sleep disabled.
    func stopSync() {
        stopMonitoring()
        if let ipcObserver {
            DistributedNotificationCenter.default().removeObserver(ipcObserver)
            self.ipcObserver = nil
        }
        assertions.releaseAll()
        do {
            try AwakeStore.withLock(timeout: 2.0) {
                var diskJournal = AwakeStore.readJournal()
                if diskJournal.sleepDisabledByUs {
                    try? PmsetBridge.setSleepDisabled(false)
                    diskJournal.sleepDisabledByUs = false
                }
                if diskJournal.lowPowerSetByUs {
                    try? PmsetBridge.setLowPowerMode(false)
                    diskJournal.lowPowerSetByUs = false
                }
                try? AwakeStore.writeJournal(diskJournal)
                AwakeStore.removeSession()
            }
        } catch {
            // Best effort on quit; backstop remains armed if lock couldn't be acquired.
        }
        AwakeBackstopAgent.disarm()
        session = nil
        journal = AwakeJournal()
        countdownText = ""
        closedLidProtected = false
        writeStatus()
    }

    @discardableResult
    func startSession(duration: TimeInterval) async -> (ok: Bool, message: String) {
        let config = Preferences.currentAwakeConfig
        let next = AwakeSession.start(duration: duration, now: Date(), keepDisplayAwake: config.keepDisplayAwake)
        let remaining = next.remaining(at: Date())

        let ready = await Task.detached(priority: .utility) { PmsetBridge.isPasswordlessSudoAvailable() }.value
        sudoersReady = ready

        var closedLid = false
        var errorMessage: String?

        // Always acquire process-scoped IOKit assertions first (works lid-open even without sudoers).
        assertions.acquire(keepDisplayAwake: config.keepDisplayAwake, timeout: remaining)

        let diskOutcome: (journal: AwakeJournal, closedLid: Bool, error: String?) = await Task.detached(priority: .userInitiated) {
            do {
                return try AwakeStore.withLock {
                    try AwakeStore.writeSession(next)
                    var diskJournal = AwakeStore.readJournal()
                    if ready {
                        AwakeBackstopAgent.arm()
                        diskJournal.sleepDisabledByUs = true
                        try AwakeStore.writeJournal(diskJournal)
                        do {
                            try PmsetBridge.setSleepDisabled(true)
                            return (diskJournal, true, nil)
                        } catch {
                            diskJournal.sleepDisabledByUs = false
                            try? AwakeStore.writeJournal(diskJournal)
                            AwakeBackstopAgent.disarm()
                            return (diskJournal, false, error.localizedDescription)
                        }
                    } else {
                        return (diskJournal, false, nil)
                    }
                }
            } catch {
                return (AwakeStore.readJournal(), false, error.localizedDescription)
            }
        }.value

        journal = diskOutcome.journal
        closedLid = diskOutcome.closedLid
        errorMessage = diskOutcome.error

        session = next
        closedLidProtected = closedLid
        lastError = errorMessage
        wasHot = false
        tickCount = 0
        countdownText = next.formattedRemaining(at: Date())
        startMonitoring()
        await evaluateFloors()
        writeStatus()

        let mode = closedLid ? "lid-closed protected" : "lid-open only"
        return (true, "Keeping Mac awake for \(next.formattedRemaining(at: Date())) (\(mode)).")
    }

    @discardableResult
    func extendSession(by seconds: TimeInterval) async -> (ok: Bool, message: String) {
        guard let current = session else {
            return await startSession(duration: seconds)
        }
        let updated = current.extended(by: seconds, now: Date())
        let remaining = updated.remaining(at: Date())

        let saved: String? = await Task.detached(priority: .userInitiated) {
            do {
                try AwakeStore.withLock {
                    try AwakeStore.writeSession(updated)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value

        if let saved {
            lastError = saved
            writeStatus()
            return (false, saved)
        }

        session = updated
        assertions.renew(timeout: remaining)
        countdownText = updated.formattedRemaining(at: Date())
        lastError = nil
        writeStatus()
        return (true, "Extended Keep Awake — \(countdownText) remaining.")
    }

    @discardableResult
    func endSession(reason: AwakeEndReason = .user) async -> (ok: Bool, message: String) {
        stopMonitoring()
        assertions.releaseAll()

        let outcome: (journal: AwakeJournal, error: String?) = await Task.detached(priority: .userInitiated) {
            do {
                return try AwakeStore.withLock {
                    var diskJournal = AwakeStore.readJournal()
                    var errors: [String] = []
                    if diskJournal.sleepDisabledByUs {
                        do {
                            try PmsetBridge.setSleepDisabled(false)
                            diskJournal.sleepDisabledByUs = false
                        } catch {
                            errors.append(error.localizedDescription)
                        }
                    }
                    if diskJournal.lowPowerSetByUs {
                        do {
                            try PmsetBridge.setLowPowerMode(false)
                            diskJournal.lowPowerSetByUs = false
                        } catch {
                            errors.append(error.localizedDescription)
                        }
                    }
                    try? AwakeStore.writeJournal(diskJournal)
                    if !diskJournal.isDirty {
                        AwakeStore.removeSession()
                        AwakeBackstopAgent.disarm()
                    }
                    return (diskJournal, errors.isEmpty ? nil : errors.joined(separator: " "))
                }
            } catch {
                return (AwakeStore.readJournal(), error.localizedDescription)
            }
        }.value

        journal = outcome.journal
        session = nil
        countdownText = ""
        closedLidProtected = false
        wasHot = false
        lastError = outcome.error
        writeStatus()

        if reason.sleepsClosedLid, !outcome.journal.sleepDisabledByUs {
            let shouldSleep = await Task.detached(priority: .utility) {
                HardwareMonitor.isLidClosedWithoutExternalDisplay()
            }.value
            if shouldSleep {
                await Task.detached(priority: .utility) { ClosedLidSleeper.requestSleep() }.value
            }
        }

        if let error = outcome.error {
            return (false, "Stopped session with warning: \(error)")
        }
        return (true, "Keep Awake stopped; sleep restored.")
    }

    /// Live-applies Settings → Keep Awake toggle changes to a running session.
    func applySettingsChange() {
        guard let current = session else { return }
        let config = Preferences.currentAwakeConfig
        let updated = current.withDisplayAwake(config.keepDisplayAwake)
        session = updated
        assertions.setDisplayAwake(config.keepDisplayAwake, timeout: updated.remaining(at: Date()))
        Task {
            await Task.detached(priority: .utility) {
                try? AwakeStore.withLock { try? AwakeStore.writeSession(updated) }
            }.value
            await evaluateFloors()
            writeStatus()
        }
    }

    // MARK: - Launch Reconcile

    private func reconcileOnLaunch() async {
        let state: (session: AwakeSession?, journal: AwakeJournal) = await Task.detached(priority: .utility) {
            (try? AwakeStore.withLock { (AwakeStore.readSession(), AwakeStore.readJournal()) }) ?? (nil, AwakeJournal())
        }.value

        journal = state.journal
        if let saved = state.session, !saved.isExpired(at: Date()) {
            // Resume an unexpired session that survived a crash/relaunch.
            session = saved
            let remaining = saved.remaining(at: Date())
            assertions.acquire(keepDisplayAwake: saved.keepDisplayAwake, timeout: remaining)
            if sudoersReady {
                let reapplied = await Task.detached(priority: .utility) { () -> Bool in
                    AwakeBackstopAgent.arm()
                    do {
                        try PmsetBridge.setSleepDisabled(true)
                        return true
                    } catch {
                        return false
                    }
                }.value
                closedLidProtected = reapplied
            }
            countdownText = saved.formattedRemaining(at: Date())
            startMonitoring()
            await evaluateFloors()
            writeStatus()
        } else if state.session != nil || state.journal.isDirty {
            _ = await endSession(reason: .backstop)
        } else {
            AwakeBackstopAgent.disarm()
            writeStatus()
        }
    }

    // MARK: - Monitoring & Safety Floors

    private func startMonitoring() {
        stopMonitoring()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluateFloors()
            }
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await self.monitorTick()
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    private func monitorTick() async {
        guard let current = session else {
            stopMonitoring()
            return
        }
        let now = Date()
        if current.isExpired(at: now) {
            _ = await endSession(reason: .timer)
            return
        }
        let formatted = current.formattedRemaining(at: now)
        if formatted != countdownText {
            countdownText = formatted
        }
        tickCount += 1
        await evaluateFloors()
        if tickCount % 2 == 0, closedLidProtected {
            await verifySleepStillHeld()
        }
        writeStatus()
    }

    private func evaluateFloors() async {
        guard isActive else { return }
        let config = Preferences.currentAwakeConfig
        let snapshot = await Task.detached(priority: .utility) { HardwareMonitor.readSnapshot() }.value

        switch snapshot.thermal {
        case .serious, .critical: wasHot = true
        case .nominal: wasHot = false
        case .fair: break
        }

        let actions = AwakeFloorRules.evaluate(
            batteryPercent: snapshot.batteryPercent,
            isCharging: snapshot.isCharging,
            thermal: snapshot.thermal,
            wasHot: wasHot,
            lidClosed: snapshot.lidClosed,
            lowPowerSetByUs: journal.lowPowerSetByUs,
            config: config
        )

        for action in actions {
            guard isActive else { return }
            switch action {
            case .endSession(let reason):
                _ = await endSession(reason: reason)
                return
            case .enableLowPower:
                await setLowPower(true)
            case .disableLowPower:
                await setLowPower(false)
            }
        }
    }

    private func setLowPower(_ on: Bool) async {
        guard sudoersReady else { return }
        let nextJournal: AwakeJournal? = await Task.detached(priority: .utility) {
            try? AwakeStore.withLock {
                var diskJournal = AwakeStore.readJournal()
                if on {
                    // Never take ownership of Low Power Mode if the user already enabled it manually.
                    guard let currentlyOn = try? PmsetBridge.isLowPowerModeOn(), currentlyOn == false else {
                        return diskJournal
                    }
                    diskJournal.lowPowerSetByUs = true
                    try AwakeStore.writeJournal(diskJournal)
                    do {
                        try PmsetBridge.setLowPowerMode(true)
                    } catch {
                        diskJournal.lowPowerSetByUs = false
                        try? AwakeStore.writeJournal(diskJournal)
                    }
                } else if diskJournal.lowPowerSetByUs {
                    do {
                        try PmsetBridge.setLowPowerMode(false)
                        diskJournal.lowPowerSetByUs = false
                        try AwakeStore.writeJournal(diskJournal)
                    } catch {
                        // Keep journaled so end/backstop retries.
                    }
                }
                return diskJournal
            }
        }.value
        if let nextJournal { journal = nextJournal }
    }

    private func verifySleepStillHeld() async {
        let stillHeld = await Task.detached(priority: .utility) { () -> Bool in
            guard let disabled = try? PmsetBridge.isSleepDisabled() else { return true }
            if disabled { return true }
            // Another daemon cleared SleepDisabled; re-apply while our session is active.
            return (try? AwakeStore.withLock {
                guard let s = AwakeStore.readSession(), !s.isExpired(at: Date()),
                      AwakeStore.readJournal().sleepDisabledByUs
                else { return true }
                try PmsetBridge.setSleepDisabled(true)
                return true
            }) ?? false
        }.value
        if !stillHeld {
            lastError = "SleepDisabled was reset by another process."
        }
    }

    // MARK: - CLI IPC & Status

    private func startIPCListener() {
        let bundleID = ownBundleID
        ipcObserver = DistributedNotificationCenter.default().addObserver(
            forName: AwakeIPC.commandNotification(for: bundleID),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let action = notification.userInfo?[AwakeIPC.actionKey] as? String
            let seconds = notification.userInfo?[AwakeIPC.secondsKey] as? Double
            let requestID = notification.userInfo?[AwakeIPC.requestIDKey] as? String
            Task { @MainActor in
                guard let self, let action else { return }
                let result: (ok: Bool, message: String)
                switch action {
                case "start":
                    result = await self.startSession(duration: seconds ?? AwakeSession.defaultDuration)
                case "extend":
                    result = await self.extendSession(by: seconds ?? 1800)
                case "stop":
                    result = await self.endSession(reason: .user)
                default:
                    result = (false, "Unknown awake IPC action: \(action)")
                }
                if let requestID {
                    DistributedNotificationCenter.default().postNotificationName(
                        AwakeIPC.replyNotification(for: bundleID),
                        object: nil,
                        userInfo: [
                            AwakeIPC.requestIDKey: requestID,
                            AwakeIPC.okKey: result.ok,
                            AwakeIPC.messageKey: result.message,
                        ],
                        deliverImmediately: true
                    )
                }
            }
        }
    }

    private func writeStatus() {
        let snapshot = AwakeStatusSnapshot(
            pid: ProcessInfo.processInfo.processIdentifier,
            active: isActive,
            session: session,
            closedLidProtected: closedLidProtected,
            sudoersReady: sudoersReady,
            lowPowerByUs: journal.lowPowerSetByUs,
            lastError: lastError,
            updatedAt: Date()
        )
        AwakeStore.writeStatus(snapshot)
    }
}
