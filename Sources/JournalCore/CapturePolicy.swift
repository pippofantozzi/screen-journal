import Foundation

/// What the world looks like right before a capture tick.
public struct CaptureConditions: Equatable, Sendable {
    public var isPaused: Bool
    public var isLocked: Bool
    public var idleSeconds: Double
    public var frontmostBundleID: String?
    public var frontmostWindowTitle: String?

    public init(isPaused: Bool, isLocked: Bool, idleSeconds: Double, frontmostBundleID: String?, frontmostWindowTitle: String?) {
        self.isPaused = isPaused
        self.isLocked = isLocked
        self.idleSeconds = idleSeconds
        self.frontmostBundleID = frontmostBundleID
        self.frontmostWindowTitle = frontmostWindowTitle
    }
}

public enum SkipReason: String, Codable, Sendable {
    case paused, locked, idle, excludedApp, privateWindow

    /// The event that opens this kind of gap in the journal.
    public var eventKind: EventRecord.Kind {
        switch self {
        case .paused: .paused
        case .locked: .locked
        case .idle: .idle
        case .excludedApp, .privateWindow: .skipped
        }
    }
}

public enum CaptureGate: Equatable, Sendable {
    case capture
    case skip(SkipReason)
}

/// Enough of a captured frame to tell whether it says anything new.
public struct FrameSignature: Equatable, Sendable {
    public let thumbnail: Thumbnail
    public let bundleID: String?
    public let windowTitle: String?

    public init(thumbnail: Thumbnail, bundleID: String?, windowTitle: String?) {
        self.thumbnail = thumbnail
        self.bundleID = bundleID
        self.windowTitle = windowTitle
    }
}

public enum FrameDecision: Equatable, Sendable {
    /// Extend the previous record.
    case unchanged
    /// Start a new record; save a screenshot only when it's worth the disk.
    case record(saveImage: Bool)
}

public struct CapturePolicy: Sendable {
    public var idleThreshold: Double
    public var excludedBundleIDs: Set<String>
    /// Below this, a frame is the same screen.
    public var minChangeRatio: Double
    /// At or above this, a frame is a new screen worth a fresh image.
    public var bigChangeRatio: Double
    /// Small changes still save an image at most this often.
    public var imageInterval: TimeInterval
    public var privateTitleMarkers: [String]
    /// This many new OCR lines earn a fresh image even when the pixels barely moved (a page finished loading).
    public var freshImageLines: Int

    public init(
        idleThreshold: Double = 120,
        excludedBundleIDs: Set<String> = [],
        minChangeRatio: Double = 0.002,
        bigChangeRatio: Double = 0.15,
        imageInterval: TimeInterval = 60,
        privateTitleMarkers: [String] = ["Private Browsing", "Incognito", "InPrivate", "Private Window"],
        freshImageLines: Int = 10
    ) {
        self.idleThreshold = idleThreshold
        self.excludedBundleIDs = excludedBundleIDs
        self.minChangeRatio = minChangeRatio
        self.bigChangeRatio = bigChangeRatio
        self.imageInterval = imageInterval
        self.privateTitleMarkers = privateTitleMarkers
        self.freshImageLines = freshImageLines
    }

    public func gate(_ c: CaptureConditions) -> CaptureGate {
        if c.isPaused { return .skip(.paused) }
        if c.isLocked { return .skip(.locked) }
        if c.idleSeconds >= idleThreshold { return .skip(.idle) }
        if let app = c.frontmostBundleID, excludedBundleIDs.contains(app) { return .skip(.excludedApp) }
        if isPrivate(c.frontmostWindowTitle) { return .skip(.privateWindow) }
        return .capture
    }

    /// `previous` is the last recorded frame on the same display.
    public func decide(current: FrameSignature, previous: FrameSignature?, lastImageAt: Date?, now: Date) -> FrameDecision {
        guard let previous else { return .record(saveImage: true) }
        if current.bundleID != previous.bundleID || current.windowTitle != previous.windowTitle {
            return .record(saveImage: true)
        }
        let ratio = current.thumbnail.changeRatio(to: previous.thumbnail)
        if ratio < minChangeRatio { return .unchanged }
        if ratio >= bigChangeRatio { return .record(saveImage: true) }
        guard let lastImageAt else { return .record(saveImage: true) }
        return .record(saveImage: now.timeIntervalSince(lastImageAt) >= imageInterval)
    }

    /// Whether to save an image once OCR has shown how much new text the frame brought.
    public func needsFreshImage(decided saveImage: Bool, newLineCount: Int) -> Bool {
        saveImage || newLineCount >= freshImageLines
    }

    private func isPrivate(_ title: String?) -> Bool {
        guard let title else { return false }
        return privateTitleMarkers.contains { title.range(of: $0, options: .caseInsensitive) != nil }
    }
}
