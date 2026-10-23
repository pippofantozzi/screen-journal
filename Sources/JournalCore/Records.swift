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
    /// The folder or file the focused window shows, or its page address; focused display only, when Accessibility allows.
    public let place: String?
    /// Latest saved image for this display, relative to the day folder. Consecutive records may share it.
    public let image: String
    /// Full on-device OCR, only on the first record of a window on this display.
    public let text: String?
    /// Lines not on screen in the previous record on this display. Nil when `text` is set.
    public let newLines: [String]?

    public init(id: String, start: Date, end: Date, display: Int, focused: Bool, app: String?, bundleID: String?,
                windowTitle: String?, place: String? = nil, image: String, text: String?, newLines: [String]?) {
        self.id = id
        self.start = start
        self.end = end
        self.display = display
        self.focused = focused
        self.app = app
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.place = place
        self.image = image
        self.text = text
        self.newLines = newLines
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// The same row showing a different image.
    func pointing(at image: String) -> FrameRecord {
        FrameRecord(id: id, start: start, end: end, display: display, focused: focused, app: app, bundleID: bundleID,
                    windowTitle: windowTitle, place: place, image: image, text: text, newLines: newLines)
    }
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
    public let windowTitle: String?
    /// The frame on screen when this happened.
    public let frameID: String?
    public let text: String?
    /// App version, on `started`.
    public let version: String?

    public init(at: Date, kind: Kind, app: String? = nil, bundleID: String? = nil, windowTitle: String? = nil,
                frameID: String? = nil, text: String? = nil, version: String? = nil) {
        self.at = at
        self.kind = kind
        self.app = app
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.frameID = frameID
        self.text = text
        self.version = version
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
