import CoreGraphics
import Foundation

/// Captured geometry and visibility of one application window prior to a Pane layout action.
public struct WindowSnapshot: Equatable, Codable, Sendable {
    public let bundleID: String
    public let pid: Int32
    public let windowTitle: String?
    public let windowIndex: Int
    public let frame: CGRect
    public let wasHidden: Bool

    public init(
        bundleID: String,
        pid: Int32,
        windowTitle: String? = nil,
        windowIndex: Int = 0,
        frame: CGRect,
        wasHidden: Bool = false
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.windowTitle = windowTitle
        self.windowIndex = windowIndex
        self.frame = frame
        self.wasHidden = wasHidden
    }
}

/// A restorable snapshot of window frames and the frontmost app before an action ran.
public struct LayoutSnapshot: Equatable, Codable, Sendable {
    public let reason: String
    public let timestamp: Date
    public let previousFrontmostBundleID: String?
    public let windows: [WindowSnapshot]

    public init(
        reason: String,
        timestamp: Date = Date(),
        previousFrontmostBundleID: String?,
        windows: [WindowSnapshot]
    ) {
        self.reason = reason
        self.timestamp = timestamp
        self.previousFrontmostBundleID = previousFrontmostBundleID
        self.windows = windows
    }
}

/// Bounded undo stack supporting `⌃⌥U` restoration.
public struct UndoStack: Equatable, Sendable {
    public let capacity: Int
    private var items: [LayoutSnapshot] = []

    public init(capacity: Int = 20) {
        self.capacity = max(1, capacity)
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var latest: LayoutSnapshot? { items.last }

    public mutating func push(_ snapshot: LayoutSnapshot) {
        items.append(snapshot)
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
    }

    @discardableResult
    public mutating func pop() -> LayoutSnapshot? {
        items.popLast()
    }

    public mutating func clear() {
        items.removeAll()
    }
}

/// Tracks toggleable overlay scenes (`Drop & Send` and `Grok Bot Drawer`) so a second press
/// cleanly hides the overlay apps and restores the pre-overlay window frames + previous frontmost app.
public enum OverlayKind: String, Equatable, Codable, Sendable {
    case dropAndSend = "drop-and-send"
    case grokDrawer = "grok-drawer"

    public var appsToHideOnDismiss: [ManagedApp] {
        switch self {
        case .dropAndSend: return [.finder, .whatsapp]
        case .grokDrawer: return [.grokBot]
        }
    }
}

/// Result of pressing a toggleable overlay hotkey (`⌃⌥W` or `⌃⌥G`).
public enum OverlayToggleTransition: Equatable, Sendable {
    case activate(OverlayKind)
    case dismiss(OverlayKind, snapshot: LayoutSnapshot, appsToHide: [ManagedApp])
}

/// Pure state machine coordinating toggle-back overlays alongside the general undo stack.
public struct LayoutHistory: Equatable, Sendable {
    public private(set) var undoStack: UndoStack
    public private(set) var activeOverlay: OverlayKind?
    public private(set) var activeOverlaySnapshot: LayoutSnapshot?

    public init(capacity: Int = 20) {
        self.undoStack = UndoStack(capacity: capacity)
    }

    public var isDropAndSendActive: Bool { activeOverlay == .dropAndSend }
    public var isGrokDrawerActive: Bool { activeOverlay == .grokDrawer }

    public mutating func toggleOverlay(
        _ kind: OverlayKind,
        overlayVisible: Bool,
        captureSnapshot: () -> LayoutSnapshot
    ) -> OverlayToggleTransition {
        if activeOverlay == kind, overlayVisible, let saved = activeOverlaySnapshot {
            activeOverlay = nil
            activeOverlaySnapshot = nil
            return .dismiss(kind, snapshot: saved, appsToHide: kind.appsToHideOnDismiss)
        }

        let snapshot = captureSnapshot()
        activeOverlay = kind
        activeOverlaySnapshot = snapshot
        undoStack.push(snapshot)
        return .activate(kind)
    }

    public mutating func recordAction(_ snapshot: LayoutSnapshot) {
        activeOverlay = nil
        activeOverlaySnapshot = nil
        undoStack.push(snapshot)
    }

    @discardableResult
    public mutating func popUndo() -> LayoutSnapshot? {
        activeOverlay = nil
        activeOverlaySnapshot = nil
        return undoStack.pop()
    }
}
