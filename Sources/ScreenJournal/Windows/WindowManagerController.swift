import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import PaneCore

/// Coordinates Pane window management inside Screen Journal: global `⌃⌥` hotkeys, display profiles,
/// AX placement, toggle-back overlays, undo stack, and CLI IPC.
@MainActor
@Observable
final class WindowManagerController {
    private(set) var isEnabled: Bool = Preferences.isWindowManagerEnabled
    private(set) var isTrusted: Bool = WindowContext.isTrusted
    private(set) var profile: DisplayProfile = DisplayManager.currentProfile()
    private(set) var activeRightBrowser: ManagedApp = .zen
    private(set) var isDropAndSendActive: Bool = false
    private(set) var isGrokDrawerActive: Bool = false
    private(set) var undoDepth: Int = 0
    private(set) var registeredHotKeys: Int = 0
    private(set) var failedHotKeys: [String] = []
    private(set) var lastActionLabel: String?

    private let engine = AXWindowEngine()
    private let hotKeys = HotKeyCenter()
    private var displayManager: DisplayManager?
    private var history = LayoutHistory(capacity: 20)

    private var currentFrontmostBundleID: String?
    private var previousFrontmostBundleID: String?
    private var workspaceObserver: NSObjectProtocol?
    private var ipcObserver: NSObjectProtocol?

    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? PaneIPC.defaultBundleID }

    init() {
        currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func start() {
        displayManager = DisplayManager { [weak self] next in
            guard let self else { return }
            self.profile = next
            self.writeStatus()
        }
        profile = displayManager?.profile ?? DisplayManager.currentProfile()
        isEnabled = Preferences.isWindowManagerEnabled
        isTrusted = WindowContext.isTrusted
        activeRightBrowser = ScenePlanner.activeBrowser(
            frontmostBundleID: currentFrontmostBundleID,
            lastRightBrowser: activeRightBrowser,
            runningBundleIDs: engine.runningBundleIDs(),
            installedApps: engine.installedApps()
        )

        observeFrontmostApp()
        startIPCListener()
        applyEnabledState()
        writeStatus()
    }

    func stop() {
        hotKeys.tearDown()
        displayManager?.stop()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let ipcObserver {
            DistributedNotificationCenter.default().removeObserver(ipcObserver)
            self.ipcObserver = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        applyEnabledState()
        writeStatus()
    }

    func refreshStatus() {
        let trusted = WindowContext.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        displayManager?.refresh()
        writeStatus()
    }

    // MARK: - Action Dispatch

    @discardableResult
    func perform(_ action: PaneAction) async -> (ok: Bool, message: String) {
        refreshStatus()

        guard isTrusted else {
            let msg = "Accessibility permission required. Allow it in Screen Journal Settings → Windows."
            lastActionLabel = "Needs Accessibility"
            writeStatus()
            return (false, msg)
        }

        let result: (ok: Bool, message: String)
        switch action {
        case .send:
            result = await toggleDropAndSend()
        case .dev:
            result = await runDevSplit()
        case .swapBrowser:
            result = await runSwapRightBrowser()
        case .dualBrowser:
            result = await runDualBrowser()
        case .grok:
            result = await toggleGrokDrawer()
        case .undo:
            result = runUndo()
        case .snapLeft, .snapRight, .snapMax, .snapLeftThird, .snapRightTwoThirds:
            result = runSnap(action.snapSlot ?? .maximize)
        case .summonGhostty, .summonZen, .summonChrome, .summonSafari, .summonFinder:
            if let app = action.summonApp {
                result = await runSummon(app)
            } else {
                result = (false, "Unknown app")
            }
        }

        syncHistoryFlags()
        lastActionLabel = result.message
        writeStatus()
        return result
    }

    // MARK: - Tailored Scenes

    private func toggleDropAndSend() async -> (Bool, String) {
        guard engine.isInstalled(.whatsapp) else {
            return (true, "WhatsApp isn't installed on this Mac.")
        }

        let visible = engine.isAppVisible(.finder) && engine.isAppVisible(.whatsapp)
        let frontBefore = currentFrontmostBundleID

        let transition = history.toggleOverlay(.dropAndSend, overlayVisible: visible) {
            engine.captureSnapshot(
                reason: "Drop & Send",
                bundleIDs: [ManagedApp.finder.bundleID, ManagedApp.whatsapp.bundleID],
                previousFrontmostBundleID: frontBefore
            )
        }

        switch transition {
        case .dismiss(_, let snapshot, let appsToHide):
            engine.restoreSnapshot(snapshot, profile: profile, hideApps: appsToHide)
            return (true, "Restored layout (hid Finder & WhatsApp)")

        case .activate:
            let plan = ScenePlanner.dropAndSend(profile: profile)
            await execute(plan: plan)
            return (true, plan.summary)
        }
    }

    private func runDevSplit() async -> (Bool, String) {
        let installed = engine.installedApps()
        let browser = ScenePlanner.activeBrowser(
            frontmostBundleID: currentFrontmostBundleID,
            lastRightBrowser: activeRightBrowser,
            runningBundleIDs: engine.runningBundleIDs(),
            installedApps: installed
        )
        activeRightBrowser = browser

        let plan = ScenePlanner.devSplit(profile: profile, browser: browser)
        let availableTargets = plan.targets.filter { installed.contains($0.app) }
        guard !availableTargets.isEmpty else {
            return (true, "No matching Dev Split apps installed on this Mac.")
        }

        let snapshot = engine.captureSnapshot(
            reason: "Dev Split",
            bundleIDs: availableTargets.map(\.app.bundleID),
            previousFrontmostBundleID: currentFrontmostBundleID
        )
        history.recordAction(snapshot)

        await execute(plan: ScenePlan(scene: plan.scene, targets: availableTargets, focusApp: plan.focusApp, summary: plan.summary))
        return (true, plan.summary)
    }

    private func runSwapRightBrowser() async -> (Bool, String) {
        let installed = engine.installedApps()
        let (plan, nextBrowser) = ScenePlanner.swapRightBrowser(
            profile: profile,
            currentBrowser: activeRightBrowser,
            installedApps: installed
        )
        activeRightBrowser = nextBrowser

        let availableTargets = plan.targets.filter { installed.contains($0.app) }
        guard !availableTargets.isEmpty else {
            return (true, "No supported browsers installed on this Mac.")
        }

        let snapshot = engine.captureSnapshot(
            reason: "Swap Right Browser",
            bundleIDs: availableTargets.map(\.app.bundleID),
            previousFrontmostBundleID: currentFrontmostBundleID
        )
        history.recordAction(snapshot)

        await execute(plan: ScenePlan(scene: plan.scene, targets: availableTargets, focusApp: plan.focusApp, summary: plan.summary))
        return (true, plan.summary)
    }

    private func runDualBrowser() async -> (Bool, String) {
        let installed = engine.installedApps()
        let rightBrowser = ScenePlanner.dualBrowserRight(
            runningBundleIDs: engine.runningBundleIDs(),
            preferredRight: activeRightBrowser == .safari ? .safari : .chrome,
            installedApps: installed
        )
        let plan = ScenePlanner.dualBrowser(profile: profile, rightBrowser: rightBrowser)
        let availableTargets = plan.targets.filter { installed.contains($0.app) }
        guard !availableTargets.isEmpty else {
            return (true, "No supported browsers installed on this Mac.")
        }

        let snapshot = engine.captureSnapshot(
            reason: "Dual Browser Split",
            bundleIDs: availableTargets.map(\.app.bundleID),
            previousFrontmostBundleID: currentFrontmostBundleID
        )
        history.recordAction(snapshot)

        await execute(plan: ScenePlan(scene: plan.scene, targets: availableTargets, focusApp: plan.focusApp, summary: plan.summary))
        return (true, plan.summary)
    }

    private func toggleGrokDrawer() async -> (Bool, String) {
        guard engine.isInstalled(.grokBot) else {
            return (true, "Grok Bot isn't installed on this Mac.")
        }

        let visible = engine.isAppVisible(.grokBot)
        let frontBefore = currentFrontmostBundleID

        let transition = history.toggleOverlay(.grokDrawer, overlayVisible: visible) {
            engine.captureSnapshot(
                reason: "Grok Bot Drawer",
                bundleIDs: [ManagedApp.grokBot.bundleID],
                previousFrontmostBundleID: frontBefore
            )
        }

        switch transition {
        case .dismiss(_, let snapshot, let appsToHide):
            engine.restoreSnapshot(snapshot, profile: profile, hideApps: appsToHide)
            return (true, "Hid Grok Bot & restored focus")

        case .activate:
            let plan = ScenePlanner.grokDrawer(profile: profile)
            await execute(plan: plan)
            return (true, plan.summary)
        }
    }

    private func runUndo() -> (Bool, String) {
        guard let snapshot = history.popUndo() else {
            return (false, "Nothing to undo")
        }
        engine.restoreSnapshot(snapshot, profile: profile)
        return (true, "Undid \(snapshot.reason)")
    }

    private func runSnap(_ slot: SnapSlot) -> (Bool, String) {
        guard let window = engine.frontmostWindow() else {
            return (false, "No standard frontmost window to snap")
        }

        let snapshot = LayoutSnapshot(
            reason: "Snap \(window.bundleID)",
            previousFrontmostBundleID: window.bundleID,
            windows: [
                WindowSnapshot(
                    bundleID: window.bundleID,
                    pid: window.pid,
                    windowTitle: window.title,
                    windowIndex: window.index,
                    frame: window.frame,
                    wasHidden: false
                ),
            ]
        )
        history.recordAction(snapshot)

        let display = profile.display(containing: window.frame)
        let constraint = AppConstraint.forBundleID(window.bundleID)
        let targetFrame = ScreenGeometry.frame(for: slot, in: display.visibleFrame, constraint: constraint)
        engine.setWindowFrame(window, to: targetFrame, profile: profile)
        return (true, "Snapped \(ManagedApp.from(bundleID: window.bundleID)?.displayName ?? "window")")
    }

    private func runSummon(_ app: ManagedApp) async -> (Bool, String) {
        let installed = engine.isInstalled(app)
        let running = engine.runningApp(bundleID: app.bundleID)
        let isFrontmost = currentFrontmostBundleID == app.bundleID
        let windowCount = running.map { engine.standardWindows(for: $0).count } ?? 0

        let decision = ScenePlanner.summonDecision(
            for: app,
            isInstalled: installed,
            isRunning: running != nil,
            isFrontmost: isFrontmost,
            standardWindowCount: windowCount
        )

        switch decision {
        case .unavailable:
            return (true, "\(app.displayName) isn't installed on this Mac.")

        case .launch:
            _ = await engine.launch(bundleID: app.bundleID)
            return (true, "Launched \(app.displayName)")

        case .activate(_, let autoOpenDownloads):
            if let (runningApp, win) = await engine.ensureWindow(for: app, autoOpenDownloadsIfEmpty: autoOpenDownloads) {
                engine.raise(win, activate: runningApp)
            } else {
                running?.unhide()
                running?.activate()
            }
            return (true, "Summoned \(app.displayName)")

        case .cycleWindows:
            if let running {
                _ = engine.cycleNextWindow(for: running)
            }
            return (true, "Cycled \(app.displayName) windows")

        case .hideAndRestorePrevious:
            engine.hide(bundleID: app.bundleID)
            if let prev = previousFrontmostBundleID,
               prev != app.bundleID,
               let prevApp = engine.runningApp(bundleID: prev) {
                if prevApp.isHidden { prevApp.unhide() }
                prevApp.activate()
            }
            return (true, "Hid \(app.displayName)")
        }
    }

    private func execute(plan: ScenePlan) async {
        var placed: [(ManagedApp, NSRunningApplication, AXWindowEngine.ManagedWindow)] = []

        for target in plan.targets {
            guard let (app, window) = await engine.ensureWindow(
                for: target.app,
                autoOpenDownloadsIfEmpty: target.autoOpenDownloadsIfEmpty
            ) else { continue }

            engine.setWindowFrame(window, to: target.frame, profile: profile)
            placed.append((target.app, app, window))
        }

        for (managed, app, window) in placed where managed != plan.focusApp {
            engine.raise(window, activate: app)
        }
        if let focused = placed.first(where: { $0.0 == plan.focusApp }) {
            engine.raise(focused.2, activate: focused.1)
        } else if let last = placed.last {
            engine.raise(last.2, activate: last.1)
        }
    }

    // MARK: - HotKeys, Observers & IPC

    private func applyEnabledState() {
        if isEnabled {
            registerHotKeys()
        } else {
            hotKeys.unregisterAll()
            registeredHotKeys = 0
            failedHotKeys = []
        }
    }

    private func registerHotKeys() {
        let ctrlOpt = UInt32(controlKey | optionKey)
        let dispatch: (PaneAction) -> (@MainActor () -> Void) = { [weak self] action in
            {
                guard let self else { return }
                Task { @MainActor in
                    _ = await self.perform(action)
                }
            }
        }

        // Zero-collision ⌃⌥ bindings (never touches Right ⌘ dictation, Left ⌘ WhatsApp export, ⌥Space note, Ctrl+`, or Cmd+Space).
        let bindings: [HotKeyCenter.Binding] = [
            .init(label: "⌃⌥W", keyCode: UInt32(kVK_ANSI_W), modifiers: ctrlOpt, action: dispatch(.send)),
            .init(label: "⌃⌥1", keyCode: UInt32(kVK_ANSI_1), modifiers: ctrlOpt, action: dispatch(.dev)),
            .init(label: "⌃⌥B", keyCode: UInt32(kVK_ANSI_B), modifiers: ctrlOpt, action: dispatch(.swapBrowser)),
            .init(label: "⌃⌥2", keyCode: UInt32(kVK_ANSI_2), modifiers: ctrlOpt, action: dispatch(.dualBrowser)),
            .init(label: "⌃⌥G", keyCode: UInt32(kVK_ANSI_G), modifiers: ctrlOpt, action: dispatch(.grok)),
            .init(label: "⌃⌥T", keyCode: UInt32(kVK_ANSI_T), modifiers: ctrlOpt, action: dispatch(.summonGhostty)),
            .init(label: "⌃⌥Z", keyCode: UInt32(kVK_ANSI_Z), modifiers: ctrlOpt, action: dispatch(.summonZen)),
            .init(label: "⌃⌥C", keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt, action: dispatch(.summonChrome)),
            .init(label: "⌃⌥S", keyCode: UInt32(kVK_ANSI_S), modifiers: ctrlOpt, action: dispatch(.summonSafari)),
            .init(label: "⌃⌥F", keyCode: UInt32(kVK_ANSI_F), modifiers: ctrlOpt, action: dispatch(.summonFinder)),
            .init(label: "⌃⌥←", keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt, action: dispatch(.snapLeft)),
            .init(label: "⌃⌥→", keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt, action: dispatch(.snapRight)),
            .init(label: "⌃⌥↩", keyCode: UInt32(kVK_Return), modifiers: ctrlOpt, action: dispatch(.snapMax)),
            .init(label: "⌃⌥[", keyCode: UInt32(kVK_ANSI_LeftBracket), modifiers: ctrlOpt, action: dispatch(.snapLeftThird)),
            .init(label: "⌃⌥]", keyCode: UInt32(kVK_ANSI_RightBracket), modifiers: ctrlOpt, action: dispatch(.snapRightTwoThirds)),
            .init(label: "⌃⌥U", keyCode: UInt32(kVK_ANSI_U), modifiers: ctrlOpt, action: dispatch(.undo)),
        ]

        hotKeys.registerAll(bindings)
        registeredHotKeys = hotKeys.registeredCount
        failedHotKeys = hotKeys.failedLabels
    }

    private func observeFrontmostApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            Task { @MainActor in
                guard let self, let bundleID, bundleID != self.ownBundleID else { return }
                if self.currentFrontmostBundleID != bundleID {
                    self.previousFrontmostBundleID = self.currentFrontmostBundleID
                    self.currentFrontmostBundleID = bundleID
                }
            }
        }
    }

    private func startIPCListener() {
        let bundleID = ownBundleID
        ipcObserver = DistributedNotificationCenter.default().addObserver(
            forName: PaneIPC.commandNotification(for: bundleID),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawAction = notification.userInfo?[PaneIPC.actionKey] as? String
            let requestID = notification.userInfo?[PaneIPC.requestIDKey] as? String
            Task { @MainActor in
                guard let self, let rawAction, let action = PaneAction(rawValue: rawAction) else { return }
                let (ok, message) = await self.perform(action)
                if let requestID {
                    DistributedNotificationCenter.default().postNotificationName(
                        PaneIPC.replyNotification(for: bundleID),
                        object: nil,
                        userInfo: [
                            PaneIPC.requestIDKey: requestID,
                            PaneIPC.okKey: ok,
                            PaneIPC.messageKey: message,
                        ],
                        deliverImmediately: true
                    )
                }
            }
        }
    }

    private func syncHistoryFlags() {
        isDropAndSendActive = history.isDropAndSendActive
        isGrokDrawerActive = history.isGrokDrawerActive
        undoDepth = history.undoStack.count
    }

    private func writeStatus() {
        let status = PaneStatus(
            pid: ProcessInfo.processInfo.processIdentifier,
            enabled: isEnabled,
            accessibilityTrusted: isTrusted,
            profile: profile,
            activeRightBrowser: activeRightBrowser,
            dropAndSendActive: isDropAndSendActive,
            grokDrawerActive: isGrokDrawerActive,
            undoDepth: undoDepth,
            registeredHotKeys: registeredHotKeys,
            failedHotKeys: failedHotKeys,
            lastAction: lastActionLabel,
            updatedAt: Date()
        )
        let url = PaneIPC.statusFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PaneStatus.encode(status)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort status file.
        }
    }
}
