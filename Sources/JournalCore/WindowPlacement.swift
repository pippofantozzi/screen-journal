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

public enum WindowPlacement {
    /// The frontmost ordinary window whose center sits on `display`.
    public static func topWindow(on display: CGRect, among windows: [WindowInfo], minSide: CGFloat = 80) -> WindowInfo? {
        windows.first(where: { w in
            w.layer == 0
                && w.bounds.width >= minSide && w.bounds.height >= minSide
                && display.contains(CGPoint(x: w.bounds.midX, y: w.bounds.midY))
        })
    }
}
