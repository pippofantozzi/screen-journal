import Foundation

/// One distinct screen state on one display, from when it appeared until it changed.
public struct FrameRecord: Codable, Equatable, Sendable {
    public let id: String
    public let start: Date
    public var end: Date
    public let display: Int
    /// True for the display holding the frontmost app.
    public let focused: Bool
    public let app: String?
    public let bundleID: String?
    public let windowTitle: String?
    /// Path relative to the day folder.
    public let image: String
    /// On-device OCR. Nil when identical to an earlier frame (see `textSameAs`).
    public let text: String?
    public let textSameAs: String?

    public init(id: String, start: Date, end: Date, display: Int, focused: Bool, app: String?, bundleID: String?,
                windowTitle: String?, image: String, text: String?, textSameAs: String?) {
        self.id = id
        self.start = start
        self.end = end
        self.display = display
        self.focused = focused
        self.app = app
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.image = image
        self.text = text
        self.textSameAs = textSameAs
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct EventRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// `paused`, `idle`, `locked`, `skipped` start a gap; `active` ends it.
        case started, stopped, paused, idle, locked, skipped, active, appSwitch, note
    }

    public let at: Date
    public let kind: Kind
    public let app: String?
    public let bundleID: String?
    public let text: String?

    public init(at: Date, kind: Kind, app: String? = nil, bundleID: String? = nil, text: String? = nil) {
        self.at = at
        self.kind = kind
        self.app = app
        self.bundleID = bundleID
        self.text = text
    }
}

/// A focused stretch of time in one window.
public struct Session: Codable, Equatable, Sendable {
    public let start: Date
    public var end: Date
    public let app: String?
    public let bundleID: String?
    public let windowTitle: String?
    public var frames: Int
    public var representativeFrame: String

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
