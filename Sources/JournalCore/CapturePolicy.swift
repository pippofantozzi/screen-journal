/// What the world looks like right before a capture tick.
public struct CaptureConditions: Equatable, Sendable {
    public var isPaused: Bool
    public var isLocked: Bool
    public var idleSeconds: Double
    public var frontmostBundleID: String?

    public init(isPaused: Bool, isLocked: Bool, idleSeconds: Double, frontmostBundleID: String?) {
        self.isPaused = isPaused
        self.isLocked = isLocked
        self.idleSeconds = idleSeconds
        self.frontmostBundleID = frontmostBundleID
    }
}

public enum SkipReason: String, Codable, Sendable {
    case paused, locked, idle, excludedApp

    /// The event that opens this kind of gap in the journal.
    public var eventKind: EventRecord.Kind {
        switch self {
        case .paused: .paused
        case .locked: .locked
        case .idle: .idle
        case .excludedApp: .skipped
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
    case keep
    case unchanged
}

public struct CapturePolicy: Sendable {
    public var idleThreshold: Double
    public var excludedBundleIDs: Set<String>
    public var minChangeRatio: Double

    public init(idleThreshold: Double = 120, excludedBundleIDs: Set<String> = [], minChangeRatio: Double = 0.002) {
        self.idleThreshold = idleThreshold
        self.excludedBundleIDs = excludedBundleIDs
        self.minChangeRatio = minChangeRatio
    }

    public func gate(_ c: CaptureConditions) -> CaptureGate {
        if c.isPaused { return .skip(.paused) }
        if c.isLocked { return .skip(.locked) }
        if c.idleSeconds >= idleThreshold { return .skip(.idle) }
        if let app = c.frontmostBundleID, excludedBundleIDs.contains(app) { return .skip(.excludedApp) }
        return .capture
    }

    public func decide(current: FrameSignature, previous: FrameSignature?) -> FrameDecision {
        guard let previous else { return .keep }
        if current.bundleID != previous.bundleID || current.windowTitle != previous.windowTitle { return .keep }
        return current.thumbnail.changeRatio(to: previous.thumbnail) >= minChangeRatio ? .keep : .unchanged
    }
}
