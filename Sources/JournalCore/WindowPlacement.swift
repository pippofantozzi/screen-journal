import CoreGraphics

/// A window as reported by the window server, in front-to-back order.
public struct WindowInfo: Equatable, Sendable {
    public let app: String
    public let bundleID: String?
    public let title: String?
    public let bounds: CGRect
    public let layer: Int

    public init(app: String, bundleID: String?, title: String?, bounds: CGRect, layer: Int) {
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.bounds = bounds
        self.layer = layer
    }
}

/// System UI that must never label a frame or count as an app switch.
public enum SystemApps {
    /// Bundle IDs and process names, since the window server doesn't always report a bundle ID.
    public static let ignored: Set<String> = [
        "com.apple.SecurityAgent", "SecurityAgent",
        "com.apple.UserNotificationCenter", "UserNotificationCenter",
        "com.apple.universalAccessAuthWarn", "universalAccessAuthWarn",
        "com.apple.loginwindow", "loginwindow",
        "com.apple.controlcenter", "Control Center",
        "com.apple.notificationcenterui", "Notification Center",
        "com.apple.dock", "Dock",
        "com.apple.WindowManager", "Window Server",
        "com.apple.Spotlight", "Spotlight",
    ]

    /// True for system UI and for Screen Journal itself.
    public static func isIgnored(app: String?, bundleID: String?, ownBundleID: String?) -> Bool {
        [app, bundleID].compactMap { $0 }.contains(where: ignored.contains)
            || (bundleID != nil && bundleID == ownBundleID)
    }
}

public enum WindowPlacement {
    /// The frontmost ordinary window whose center sits on `display`,
    /// preferring one from the app with bundle ID `preferring` when it has a window there.
    public static func topWindow(
        on display: CGRect,
        among windows: [WindowInfo],
        preferring bundleID: String? = nil,
        ownBundleID: String? = nil,
        minSide: CGFloat = 80
    ) -> WindowInfo? {
        let candidates = windows.filter { w in
            w.layer == 0
                && w.bounds.width >= minSide && w.bounds.height >= minSide
                && display.contains(CGPoint(x: w.bounds.midX, y: w.bounds.midY))
                && !SystemApps.isIgnored(app: w.app, bundleID: w.bundleID, ownBundleID: ownBundleID)
        }
        let preferred = bundleID.flatMap { id in candidates.first { $0.bundleID == id } }
        return preferred ?? candidates.first
    }
}
