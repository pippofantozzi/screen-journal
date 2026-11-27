import AppKit
import ApplicationServices
import Foundation
import PaneCore

/// Low-level `AXUIElement` window controller tailored for Electron, Mac Catalyst, Gecko, Chromium, Ghostty & Finder.
/// Coordinates with `WindowContext` so Screen Journal's capture ticks never race `AXEnhancedUserInterface` during moves.
@MainActor
final class AXWindowEngine {
    struct ManagedWindow {
        let element: AXUIElement
        let appElement: AXUIElement
        let pid: pid_t
        let bundleID: String
        let title: String?
        let frame: CGRect
        let index: Int
    }

    private let enhancedUIAttribute = "AXEnhancedUserInterface" as CFString
    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? PaneIPC.defaultBundleID }

    // MARK: - App Availability & Reading Windows

    func isInstalled(_ app: ManagedApp) -> Bool {
        runningApp(bundleID: app.bundleID) != nil
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    func installedApps() -> Set<ManagedApp> {
        Set(ManagedApp.allCases.filter(isInstalled))
    }

    /// Returns all standard windows (`AXRole == AXWindow` && `AXSubrole == AXStandardWindow`) for `app`.
    /// Filters out Chrome helper popups/bubbles and Finder's Desktop window.
    func standardWindows(for app: NSRunningApplication, includeMinimized: Bool = false) -> [ManagedWindow] {
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? ""
        let appElement = AXUIElementCreateApplication(pid)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let rawWindows = value as? [AXUIElement]
        else {
            return []
        }

        var result: [ManagedWindow] = []
        for (idx, win) in rawWindows.enumerated() {
            guard isStandardWindow(win) else { continue }
            if !includeMinimized && isMinimized(win) { continue }
            guard let frame = windowFrame(win) else { continue }
            let title = stringAttribute(win, kAXTitleAttribute as CFString)
            result.append(ManagedWindow(
                element: win,
                appElement: appElement,
                pid: pid,
                bundleID: bundleID,
                title: title,
                frame: frame,
                index: idx
            ))
        }
        return result
    }

    func frontmostWindow() -> ManagedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleID
        else { return nil }

        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? ""
        let appElement = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let cfFocused = focused,
           CFGetTypeID(cfFocused) == AXUIElementGetTypeID() {
            let win = unsafeDowncast(cfFocused, to: AXUIElement.self)
            if isStandardWindow(win), let frame = windowFrame(win) {
                return ManagedWindow(
                    element: win,
                    appElement: appElement,
                    pid: pid,
                    bundleID: bundleID,
                    title: stringAttribute(win, kAXTitleAttribute as CFString),
                    frame: frame,
                    index: 0
                )
            }
        }
        return standardWindows(for: app).first
    }

    func runningApp(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isAppVisible(_ app: ManagedApp) -> Bool {
        guard let running = runningApp(bundleID: app.bundleID), !running.isHidden else { return false }
        return !standardWindows(for: running).isEmpty
    }

    // MARK: - Snapshots

    func captureSnapshot(
        reason: String,
        bundleIDs: [String],
        previousFrontmostBundleID: String?
    ) -> LayoutSnapshot {
        var uniqueIDs = bundleIDs
        if let front = previousFrontmostBundleID, !uniqueIDs.contains(front) {
            uniqueIDs.append(front)
        }

        var captured: [WindowSnapshot] = []
        for id in uniqueIDs {
            guard id != ownBundleID, let running = runningApp(bundleID: id) else { continue }
            let wins = standardWindows(for: running, includeMinimized: true)
            if let first = wins.first {
                captured.append(WindowSnapshot(
                    bundleID: id,
                    pid: running.processIdentifier,
                    windowTitle: first.title,
                    windowIndex: first.index,
                    frame: first.frame,
                    wasHidden: running.isHidden
                ))
            }
        }

        return LayoutSnapshot(
            reason: reason,
            previousFrontmostBundleID: previousFrontmostBundleID,
            windows: captured
        )
    }

    func restoreSnapshot(_ snapshot: LayoutSnapshot, profile: DisplayProfile, hideApps: [ManagedApp] = []) {
        for app in hideApps {
            hide(bundleID: app.bundleID)
        }

        let hiddenIDs = Set(hideApps.map(\.bundleID))
        for item in snapshot.windows {
            guard let running = runningApp(bundleID: item.bundleID) else { continue }
            if hiddenIDs.contains(item.bundleID) {
                if let win = matchWindow(for: running, snapshot: item) {
                    setWindowFrame(win, to: item.frame, profile: profile)
                }
                running.hide()
                continue
            }
            if !item.wasHidden && running.isHidden {
                running.unhide()
            }
            if let win = matchWindow(for: running, snapshot: item) {
                unminimizeIfNeeded(win.element)
                setWindowFrame(win, to: item.frame, profile: profile)
            }
        }

        if let prevID = snapshot.previousFrontmostBundleID,
           prevID != ownBundleID,
           !hiddenIDs.contains(prevID),
           let prevApp = runningApp(bundleID: prevID) {
            if prevApp.isHidden { prevApp.unhide() }
            prevApp.activate()
        }
    }

    // MARK: - App Preparation & Placement

    /// Ensures `app` is installed, running, unhidden, and has a standard window ready to place.
    /// Returns `nil` silently (no alert/crash) when `app` isn't installed on this Mac.
    func ensureWindow(
        for app: ManagedApp,
        autoOpenDownloadsIfEmpty: Bool = false
    ) async -> (NSRunningApplication, ManagedWindow)? {
        guard isInstalled(app) else { return nil }

        var running = runningApp(bundleID: app.bundleID)
        if running == nil {
            running = await launch(bundleID: app.bundleID)
        }
        guard let running else { return nil }

        if running.isHidden {
            running.unhide()
        }

        if let visible = standardWindows(for: running).first {
            return (running, visible)
        }

        if let minimized = standardWindows(for: running, includeMinimized: true).first {
            unminimizeIfNeeded(minimized.element)
            try? await Task.sleep(for: .milliseconds(80))
            if let refreshed = standardWindows(for: running).first {
                return (running, refreshed)
            }
            return (running, minimized)
        }

        if app == .finder && autoOpenDownloadsIfEmpty {
            openDownloadsInFinder()
            if let opened = await waitForStandardWindow(for: running, timeoutMs: 1200) {
                return (running, opened)
            }
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } else {
            running.activate()
        }

        if let opened = await waitForStandardWindow(for: running, timeoutMs: 1200) {
            return (running, opened)
        }
        return nil
    }

    /// Moves and resizes `window` to `targetFrame`, coordinating with `WindowContext` and applying all per-app AX quirks.
    func setWindowFrame(
        _ window: ManagedWindow,
        to targetFrame: CGRect,
        profile: DisplayProfile
    ) {
        WindowContext.beginWindowMove(of: window.pid)
        defer { WindowContext.endWindowMove(of: window.pid) }

        let constraint = AppConstraint.forBundleID(window.bundleID)
        unminimizeIfNeeded(window.element)

        let restoreEnhancedUI: Bool
        if constraint.disableEnhancedUIOnMove {
            restoreEnhancedUI = temporarilyDisableEnhancedUI(on: window.appElement)
        } else {
            restoreEnhancedUI = false
        }
        defer {
            if restoreEnhancedUI {
                setBoolAttribute(window.appElement, enhancedUIAttribute, value: true)
            }
        }

        let currentDisplay = profile.display(containing: window.frame)
        let targetDisplay = profile.display(containing: targetFrame)
        let crossesDisplay = currentDisplay.id != targetDisplay.id

        if constraint.needsPositionSizePosition && crossesDisplay {
            setPosition(window.element, point: targetFrame.origin)
            setSize(window.element, size: targetFrame.size)
            setPosition(window.element, point: targetFrame.origin)
            setSize(window.element, size: targetFrame.size)
        } else {
            setPosition(window.element, point: targetFrame.origin)
            setSize(window.element, size: targetFrame.size)

            if let after = windowFrame(window.element),
               !ScreenGeometry.framesMatch(after, targetFrame, tolerance: constraint.cellTolerance) {
                setPosition(window.element, point: targetFrame.origin)
                setSize(window.element, size: targetFrame.size)
            }
        }
    }

    func raise(_ window: ManagedWindow, activate app: NSRunningApplication? = nil) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        app?.activate()
    }

    func cycleNextWindow(for app: NSRunningApplication) -> Bool {
        let windows = standardWindows(for: app)
        guard windows.count > 1 else { return false }
        let target = windows.last ?? windows[1]
        AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.activate()
        return true
    }

    func hide(bundleID: String) {
        runningApp(bundleID: bundleID)?.hide()
    }

    func launch(bundleID: String) async -> NSRunningApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    func openDownloadsInFinder() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        if FileManager.default.fileExists(atPath: downloads.path) {
            NSWorkspace.shared.open(downloads)
        } else {
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    // MARK: - Private AX Helpers

    private func waitForStandardWindow(for app: NSRunningApplication, timeoutMs: Int) async -> ManagedWindow? {
        let steps = max(1, timeoutMs / 60)
        for _ in 0..<steps {
            if let win = standardWindows(for: app).first {
                return win
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        return standardWindows(for: app).first
    }

    private func matchWindow(for app: NSRunningApplication, snapshot: WindowSnapshot) -> ManagedWindow? {
        let windows = standardWindows(for: app, includeMinimized: true)
        if let title = snapshot.windowTitle,
           let byTitle = windows.first(where: { $0.title == title }) {
            return byTitle
        }
        if let byIndex = windows.first(where: { $0.index == snapshot.windowIndex }) {
            return byIndex
        }
        return windows.first
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString)
        return role == (kAXWindowRole as String) && subrole == (kAXStandardWindowSubrole as String)
    }

    private func isMinimized(_ element: AXUIElement) -> Bool {
        boolAttribute(element, kAXMinimizedAttribute as CFString) == true
    }

    private func unminimizeIfNeeded(_ element: AXUIElement) {
        if isMinimized(element) {
            setBoolAttribute(element, kAXMinimizedAttribute as CFString, value: false)
        }
    }

    private func temporarilyDisableEnhancedUI(on appElement: AXUIElement) -> Bool {
        guard boolAttribute(appElement, enhancedUIAttribute) == true else { return false }
        return AXUIElementSetAttributeValue(appElement, enhancedUIAttribute, kCFBooleanFalse) == .success
    }

    private func windowFrame(_ element: AXUIElement) -> CGRect? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func setPosition(_ element: AXUIElement, point: CGPoint) {
        var mutable = point
        if let value = AXValueCreate(.cgPoint, &mutable) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    private func setSize(_ element: AXUIElement, size: CGSize) {
        var mutable = size
        if let value = AXValueCreate(.cgSize, &mutable) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func setBoolAttribute(_ element: AXUIElement, _ attribute: CFString, value: Bool) {
        AXUIElementSetAttributeValue(element, attribute, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(raw, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(raw, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}
