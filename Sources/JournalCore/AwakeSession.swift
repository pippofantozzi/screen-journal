import Foundation

/// A timed keep-awake session. Never an open-ended toggle: every session has an end time.
public struct AwakeSession: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let endsAt: Date
    public let keepDisplayAwake: Bool

    public static let maxDuration: TimeInterval = 30 * 24 * 3600
    public static let defaultDuration: TimeInterval = 4 * 3600
    public static let presets: [TimeInterval] = [1800, 3600, 7200, 14400, 28800]
    public static let extendPresets: [TimeInterval] = [1800, 3600, 7200]

    public init(startedAt: Date, endsAt: Date, keepDisplayAwake: Bool = false) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.keepDisplayAwake = keepDisplayAwake
    }

    public static func start(duration: TimeInterval, now: Date, keepDisplayAwake: Bool = false) -> AwakeSession {
        let clamped = min(max(60, duration), maxDuration)
        return AwakeSession(startedAt: now, endsAt: now.addingTimeInterval(clamped), keepDisplayAwake: keepDisplayAwake)
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    public func isExpired(at now: Date) -> Bool {
        now >= endsAt
    }

    public func extended(by seconds: TimeInterval, now: Date) -> AwakeSession {
        let base = max(endsAt, now)
        let cap = now.addingTimeInterval(Self.maxDuration)
        let nextEnd = min(base.addingTimeInterval(max(0, seconds)), cap)
        return AwakeSession(startedAt: startedAt, endsAt: nextEnd, keepDisplayAwake: keepDisplayAwake)
    }

    public func withDisplayAwake(_ keepDisplayAwake: Bool) -> AwakeSession {
        AwakeSession(startedAt: startedAt, endsAt: endsAt, keepDisplayAwake: keepDisplayAwake)
    }

    /// Compact remaining time for the menu bar: "2d 4h", "1h 42m", "45m", "<1m".
    public func formattedRemaining(at now: Date) -> String {
        let secs = remaining(at: now)
        guard secs > 0 else { return "0m" }
        if secs < 60 { return "<1m" }
        let totalMinutes = Int(ceil(secs / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int(round(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}

/// Persisted ownership journal for privileged pmset changes so crash recovery and the backstop
/// undo only what Screen Journal changed.
public struct AwakeJournal: Codable, Equatable, Sendable {
    public var sleepDisabledByUs: Bool
    public var lowPowerSetByUs: Bool

    public init(sleepDisabledByUs: Bool = false, lowPowerSetByUs: Bool = false) {
        self.sleepDisabledByUs = sleepDisabledByUs
        self.lowPowerSetByUs = lowPowerSetByUs
    }

    public var isDirty: Bool {
        sleepDisabledByUs || lowPowerSetByUs
    }
}

public enum AwakeThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public enum AwakeEndReason: String, Codable, Equatable, Sendable {
    case timer
    case user
    case quit
    case batteryFloor
    case thermalCritical
    case backstop
    case startFailed

    /// Timer and safety-floor ends ask a closed laptop to sleep once sleep is re-enabled.
    public var sleepsClosedLid: Bool {
        switch self {
        case .timer, .batteryFloor, .thermalCritical: true
        case .user, .quit, .backstop, .startFailed: false
        }
    }
}

public struct AwakeConfig: Equatable, Sendable {
    public var keepDisplayAwake: Bool
    public var lowPowerOnLidClose: Bool
    public var lowPowerFloor: Int
    public var endFloor: Int
    public var thermalRules: Bool

    public init(
        keepDisplayAwake: Bool = false,
        lowPowerOnLidClose: Bool = true,
        lowPowerFloor: Int = 40,
        endFloor: Int = 10,
        thermalRules: Bool = true
    ) {
        self.keepDisplayAwake = keepDisplayAwake
        self.lowPowerOnLidClose = lowPowerOnLidClose
        self.lowPowerFloor = lowPowerFloor
        self.endFloor = endFloor
        self.thermalRules = thermalRules
    }
}

public enum AwakeFloorAction: Equatable, Sendable {
    case enableLowPower
    case disableLowPower
    case endSession(AwakeEndReason)
}

/// Pure battery, thermal, and lid safety rules evaluated during an active awake session.
public enum AwakeFloorRules {
    public static func evaluate(
        batteryPercent: Int?,
        isCharging: Bool,
        thermal: AwakeThermalState,
        wasHot: Bool,
        lidClosed: Bool,
        lowPowerSetByUs: Bool,
        config: AwakeConfig
    ) -> [AwakeFloorAction] {
        if config.thermalRules && thermal == .critical {
            return [.endSession(.thermalCritical)]
        }
        if !isCharging, let percent = batteryPercent, config.endFloor > 0, percent <= config.endFloor {
            return [.endSession(.batteryFloor)]
        }

        let needsLowPowerForBattery = !isCharging
            && config.lowPowerFloor > 0
            && (batteryPercent.map { $0 <= config.lowPowerFloor } ?? false)
        let needsLowPowerForThermal = config.thermalRules
            && (thermal == .serious || thermal == .critical || (wasHot && thermal != .nominal))
        let needsLowPowerForLid = config.lowPowerOnLidClose && lidClosed

        let wantsLowPower = needsLowPowerForBattery || needsLowPowerForThermal || needsLowPowerForLid

        if wantsLowPower && !lowPowerSetByUs {
            return [.enableLowPower]
        }
        if !wantsLowPower && lowPowerSetByUs {
            return [.disableLowPower]
        }
        return []
    }
}

/// Pure parsers for `pmset -g` and `pmset -g custom`.
public enum PmsetParser {
    /// Returns true for `SleepDisabled 1`, false for `SleepDisabled 0`, nil when missing or unreadable.
    public static func readSleepDisabled(_ output: String) -> Bool? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("SleepDisabled") else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[0] == "SleepDisabled" else { continue }
            switch parts[1] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        return nil
    }

    /// Reads Battery Power Low Power Mode (`lowpowermode`, or `powermode` on macOS 27+).
    public static func parseLowPowerMode(_ output: String) -> Bool? {
        var inBattery = false
        var lowPowerValue: String?
        var powerModeValue: String?
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(":") {
                inBattery = line == "Battery Power:"
                continue
            }
            guard inBattery else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let key = parts.first else { continue }
            let value = parts.count >= 2 ? String(parts[1]) : ""
            if key == "lowpowermode", lowPowerValue == nil { lowPowerValue = value }
            if key == "powermode", powerModeValue == nil { powerModeValue = value }
        }
        let chosen = lowPowerValue ?? powerModeValue
        switch chosen {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }
}

/// IPC contract between `ScreenJournal awake ...` CLI and the running app.
public enum AwakeIPC {
    public static let defaultBundleID = "com.filippofantozzi.ScreenJournal"
    public static let actionKey = "action"
    public static let secondsKey = "seconds"
    public static let requestIDKey = "requestID"
    public static let okKey = "ok"
    public static let messageKey = "message"

    public static func commandNotification(for bundleID: String = defaultBundleID) -> Notification.Name {
        Notification.Name("\(bundleID).awake.command")
    }

    public static func replyNotification(for bundleID: String = defaultBundleID) -> Notification.Name {
        Notification.Name("\(bundleID).awake.reply")
    }

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ScreenJournal", directoryHint: .isDirectory)
    }

    public static var sessionFileURL: URL {
        supportDirectory.appending(path: "awake-session.json")
    }

    public static var journalFileURL: URL {
        supportDirectory.appending(path: "awake-state.json")
    }

    public static var lockFileURL: URL {
        supportDirectory.appending(path: "awake.lock")
    }

    public static var statusFileURL: URL {
        supportDirectory.appending(path: "awake-status.json")
    }
}

public struct AwakeStatusSnapshot: Codable, Equatable, Sendable {
    public let pid: Int32
    public let active: Bool
    public let session: AwakeSession?
    public let closedLidProtected: Bool
    public let sudoersReady: Bool
    public let lowPowerByUs: Bool
    public let lastError: String?
    public let updatedAt: Date

    public init(
        pid: Int32,
        active: Bool,
        session: AwakeSession?,
        closedLidProtected: Bool,
        sudoersReady: Bool,
        lowPowerByUs: Bool,
        lastError: String?,
        updatedAt: Date
    ) {
        self.pid = pid
        self.active = active
        self.session = session
        self.closedLidProtected = closedLidProtected
        self.sudoersReady = sudoersReady
        self.lowPowerByUs = lowPowerByUs
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

public enum AwakeCLICommand: Equatable, Sendable {
    case start(seconds: TimeInterval)
    case extend(seconds: TimeInterval)
    case stop
    case status(json: Bool)
    case backstop
    case help(String)
}

public enum AwakeCLIParser {
    public static let usage = """
    Usage:
      ScreenJournal awake start <duration>    # e.g. 30m, 2h, 1h30m, 1d, or seconds (7200)
      ScreenJournal awake extend <duration>   # add time to an active session
      ScreenJournal awake stop                # end the active session and restore sleep
      ScreenJournal awake status [--json]     # show active session and protection status
      ScreenJournal awake backstop            # recovery check run by launchd
    """

    public static func parse(subcommandArguments: [String]) -> Result<AwakeCLICommand, JournalCommand.Usage> {
        guard let first = subcommandArguments.first else {
            return .success(.help(usage))
        }
        let rest = Array(subcommandArguments.dropFirst())
        switch first {
        case "--help", "-h", "help":
            return .success(.help(usage))
        case "start":
            guard rest.count == 1, let seconds = parseDuration(rest[0]), seconds >= 60 else {
                return .failure(.init(message: "awake start takes a duration of at least 1m (e.g. 30m, 2h, 1h30m, 7200).\n\n\(usage)"))
            }
            return .success(.start(seconds: min(seconds, AwakeSession.maxDuration)))
        case "extend":
            guard rest.count == 1, let seconds = parseDuration(rest[0]), seconds >= 60 else {
                return .failure(.init(message: "awake extend takes a duration of at least 1m (e.g. 30m, 1h, 1800).\n\n\(usage)"))
            }
            return .success(.extend(seconds: min(seconds, AwakeSession.maxDuration)))
        case "stop", "end":
            guard rest.isEmpty else {
                return .failure(.init(message: "awake stop takes no extra arguments.\n\n\(usage)"))
            }
            return .success(.stop)
        case "status":
            if rest.isEmpty { return .success(.status(json: false)) }
            if rest == ["--json"] { return .success(.status(json: true)) }
            return .failure(.init(message: "Unexpected arguments for awake status: \(rest.joined(separator: " "))\n\n\(usage)"))
        case "backstop":
            guard rest.isEmpty else {
                return .failure(.init(message: "awake backstop takes no extra arguments.\n\n\(usage)"))
            }
            return .success(.backstop)
        default:
            return .failure(.init(message: "Unknown awake command: \(first)\n\n\(usage)"))
        }
    }

    /// Parses bare seconds ("7200") or compact units ("30m", "2h", "1h30m", "1d12h").
    public static func parseDuration(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if let seconds = Double(text), seconds.isFinite, seconds > 0 {
            return seconds
        }
        let pattern = /^(\d+d)?(\d+h)?(\d+m)?(\d+s)?$/
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        var total: TimeInterval = 0
        if let d = match.1 { total += Double(d.dropLast())! * 86400 }
        if let h = match.2 { total += Double(h.dropLast())! * 3600 }
        if let m = match.3 { total += Double(m.dropLast())! * 60 }
        if let s = match.4 { total += Double(s.dropLast())! }
        return total > 0 ? total : nil
    }
}
