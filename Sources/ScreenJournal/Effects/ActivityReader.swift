import AppKit
import JournalCore

/// Reads what the user is doing right now: frontmost app, visible windows, idle time.
enum ActivityReader {
    static var frontmost: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// On-screen windows, front to back. Titles need the Screen Recording grant.
    static func windows() -> [WindowInfo] {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return WindowInfo(
                app: w[kCGWindowOwnerName as String] as? String ?? "Unknown",
                bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                title: WindowTitle.stable(w[kCGWindowName as String] as? String),
                bounds: bounds,
                layer: w[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }
}

/// Tracks lock and sleep through system notifications.
final class LockWatcher {
    private(set) var isLocked = false
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked", locked: true)
        observe(distributed, "com.apple.screenIsUnlocked", locked: false)
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue, locked: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue, locked: false)
    }

    private func observe(_ center: NotificationCenter, _ name: String, locked: Bool) {
        let token = center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = locked
        }
        tokens.append((center, token))
    }

    deinit { tokens.forEach { $0.0.removeObserver($0.1) } }
}
