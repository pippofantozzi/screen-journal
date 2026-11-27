import Foundation

/// All window-management actions Pane can perform via global hotkey, menu bar, or CLI IPC.
public enum PaneAction: String, CaseIterable, Codable, Equatable, Sendable {
    case send
    case dev
    case swapBrowser = "swap-browser"
    case dualBrowser = "dual-browser"
    case grok
    case undo
    case snapLeft = "snap-left"
    case snapRight = "snap-right"
    case snapMax = "snap-max"
    case snapLeftThird = "snap-left-third"
    case snapRightTwoThirds = "snap-right-two-thirds"
    case summonGhostty = "summon-ghostty"
    case summonZen = "summon-zen"
    case summonChrome = "summon-chrome"
    case summonSafari = "summon-safari"
    case summonFinder = "summon-finder"

    public var snapSlot: SnapSlot? {
        switch self {
        case .snapLeft: return .leftHalf
        case .snapRight: return .rightHalf
        case .snapMax: return .maximize
        case .snapLeftThird: return .leftThird
        case .snapRightTwoThirds: return .rightTwoThirds
        default: return nil
        }
    }

    public var summonApp: ManagedApp? {
        switch self {
        case .summonGhostty: return .ghostty
        case .summonZen: return .zen
        case .summonChrome: return .chrome
        case .summonSafari: return .safari
        case .summonFinder: return .finder
        default: return nil
        }
    }
}

/// Parsed CLI invocation for `ScreenJournal pane <subcommand>`.
public enum PaneCLICommand: Equatable, Sendable {
    case action(PaneAction)
    case status(json: Bool)
    case help(String)
}

public struct PaneCLIParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    public init(_ message: String) {
        self.message = message
    }
}

public enum PaneCLIParser {
    public static let usage = """
    Usage:
      ScreenJournal pane send                              Toggle Drop & Send (Finder 42% + WhatsApp 58%)
      ScreenJournal pane dev                               Dev Split (Ghostty 48% + active browser 52%)
      ScreenJournal pane swap-browser                      Keep Ghostty left, cycle right browser (Zen → Chrome → Safari)
      ScreenJournal pane dual-browser                      Dual Browser Split (Zen 50% + Chrome/Safari 50%)
      ScreenJournal pane grok                              Toggle Grok Bot right drawer (38%, ≥500px)
      ScreenJournal pane undo                              Undo last layout change
      ScreenJournal pane snap <slot>                       left | right | max | left-third | right-two-thirds
      ScreenJournal pane summon <app>                      ghostty | zen | chrome | safari | finder
      ScreenJournal pane status [--json]                   Show window manager, Accessibility & display profile status
    """

    /// Parses subcommand arguments after `pane` (e.g. `["send"]`, `["snap", "left"]`, `["status", "--json"]`).
    public static func parse(subcommandArguments args: [String]) -> Result<PaneCLICommand, PaneCLIParseError> {
        guard let first = args.first else {
            return .success(.help(usage))
        }

        switch first {
        case "-h", "--help", "help":
            return .success(.help(usage))

        case "send":
            return requireNoExtraArgs(args, maxCount: 1, command: "send").map { .action(.send) }

        case "dev":
            return requireNoExtraArgs(args, maxCount: 1, command: "dev").map { .action(.dev) }

        case "swap-browser":
            return requireNoExtraArgs(args, maxCount: 1, command: "swap-browser").map { .action(.swapBrowser) }

        case "dual-browser":
            return requireNoExtraArgs(args, maxCount: 1, command: "dual-browser").map { .action(.dualBrowser) }

        case "grok":
            return requireNoExtraArgs(args, maxCount: 1, command: "grok").map { .action(.grok) }

        case "undo":
            return requireNoExtraArgs(args, maxCount: 1, command: "undo").map { .action(.undo) }

        case "status":
            if args.count == 1 {
                return .success(.status(json: false))
            }
            if args.count == 2 && args[1] == "--json" {
                return .success(.status(json: true))
            }
            return .failure(PaneCLIParseError("Unknown option for status: \(args.dropFirst().joined(separator: " "))"))

        case "snap":
            guard args.count == 2 else {
                return .failure(PaneCLIParseError("Usage: ScreenJournal pane snap <left|right|max|left-third|right-two-thirds>"))
            }
            switch args[1].lowercased() {
            case "left": return .success(.action(.snapLeft))
            case "right": return .success(.action(.snapRight))
            case "max", "maximize": return .success(.action(.snapMax))
            case "left-third": return .success(.action(.snapLeftThird))
            case "right-two-thirds": return .success(.action(.snapRightTwoThirds))
            default:
                return .failure(PaneCLIParseError("Unknown snap slot '\(args[1])'. Expected: left, right, max, left-third, right-two-thirds"))
            }

        case "summon":
            guard args.count == 2 else {
                return .failure(PaneCLIParseError("Usage: ScreenJournal pane summon <ghostty|zen|chrome|safari|finder>"))
            }
            switch args[1].lowercased() {
            case "ghostty", "t": return .success(.action(.summonGhostty))
            case "zen", "z": return .success(.action(.summonZen))
            case "chrome", "c": return .success(.action(.summonChrome))
            case "safari", "s": return .success(.action(.summonSafari))
            case "finder", "f": return .success(.action(.summonFinder))
            default:
                return .failure(PaneCLIParseError("Unknown app '\(args[1])'. Expected: ghostty, zen, chrome, safari, finder"))
            }

        default:
            return .failure(PaneCLIParseError("Unknown pane command '\(first)'. Run 'ScreenJournal pane --help' for usage."))
        }
    }

    private static func requireNoExtraArgs(_ args: [String], maxCount: Int, command: String) -> Result<Void, PaneCLIParseError> {
        guard args.count <= maxCount else {
            return .failure(PaneCLIParseError("Unexpected argument for '\(command)': \(args.dropFirst(maxCount).joined(separator: " "))"))
        }
        return .success(())
    }
}

/// Shared IPC channel names scoped to the host app's bundle identifier (`com.filippofantozzi.ScreenJournal`).
public enum PaneIPC {
    public static let defaultBundleID = "com.filippofantozzi.ScreenJournal"

    public static func commandNotification(for bundleID: String = defaultBundleID) -> Notification.Name {
        Notification.Name("\(bundleID).pane.command")
    }

    public static func replyNotification(for bundleID: String = defaultBundleID) -> Notification.Name {
        Notification.Name("\(bundleID).pane.reply")
    }

    public static let actionKey = "action"
    public static let requestIDKey = "requestID"
    public static let okKey = "ok"
    public static let messageKey = "message"

    public static var statusFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "ScreenJournal", directoryHint: .isDirectory).appending(path: "pane-status.json")
    }
}

/// Serializable runtime status published by `WindowManagerController` and read by `ScreenJournal pane status`.
public struct PaneStatus: Equatable, Codable, Sendable {
    public let pid: Int32
    public let enabled: Bool
    public let accessibilityTrusted: Bool
    public let profile: DisplayProfile
    public let activeRightBrowser: ManagedApp
    public let dropAndSendActive: Bool
    public let grokDrawerActive: Bool
    public let undoDepth: Int
    public let registeredHotKeys: Int
    public let failedHotKeys: [String]
    public let lastAction: String?
    public let updatedAt: Date

    public init(
        pid: Int32,
        enabled: Bool,
        accessibilityTrusted: Bool,
        profile: DisplayProfile,
        activeRightBrowser: ManagedApp,
        dropAndSendActive: Bool,
        grokDrawerActive: Bool,
        undoDepth: Int,
        registeredHotKeys: Int,
        failedHotKeys: [String],
        lastAction: String?,
        updatedAt: Date = Date()
    ) {
        self.pid = pid
        self.enabled = enabled
        self.accessibilityTrusted = accessibilityTrusted
        self.profile = profile
        self.activeRightBrowser = activeRightBrowser
        self.dropAndSendActive = dropAndSendActive
        self.grokDrawerActive = grokDrawerActive
        self.undoDepth = undoDepth
        self.registeredHotKeys = registeredHotKeys
        self.failedHotKeys = failedHotKeys
        self.lastAction = lastAction
        self.updatedAt = updatedAt
    }

    public static func encode(_ status: PaneStatus) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(status)
    }

    public static func decode(_ data: Data) throws -> PaneStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PaneStatus.self, from: data)
    }
}

/// Static shortcut legend shown in Settings → Windows.
public struct HotKeyLegendItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let shortcut: String
    public let title: String
    public let detail: String

    public init(shortcut: String, title: String, detail: String) {
        self.id = shortcut
        self.shortcut = shortcut
        self.title = title
        self.detail = detail
    }

    public static let scenes: [HotKeyLegendItem] = [
        HotKeyLegendItem(shortcut: "⌃⌥W", title: "Drop & Send", detail: "Finder 42% + WhatsApp 58% (toggle)"),
        HotKeyLegendItem(shortcut: "⌃⌥1", title: "Dev Split", detail: "Ghostty 48% + active browser 52%"),
        HotKeyLegendItem(shortcut: "⌃⌥B", title: "Swap Right Browser", detail: "Zen → Chrome → Safari"),
        HotKeyLegendItem(shortcut: "⌃⌥2", title: "Dual Browser Split", detail: "Zen 50% + Chrome/Safari 50%"),
        HotKeyLegendItem(shortcut: "⌃⌥G", title: "Grok Bot Drawer", detail: "Right 38% ≥500px (toggle)"),
    ]

    public static let summon: [HotKeyLegendItem] = [
        HotKeyLegendItem(shortcut: "⌃⌥T", title: "Ghostty", detail: "Summon or cycle"),
        HotKeyLegendItem(shortcut: "⌃⌥Z", title: "Zen Browser", detail: "Summon or cycle"),
        HotKeyLegendItem(shortcut: "⌃⌥C", title: "Google Chrome", detail: "Summon or cycle"),
        HotKeyLegendItem(shortcut: "⌃⌥S", title: "Safari", detail: "Summon or cycle"),
        HotKeyLegendItem(shortcut: "⌃⌥F", title: "Finder", detail: "Summon or cycle"),
    ]

    public static let snaps: [HotKeyLegendItem] = [
        HotKeyLegendItem(shortcut: "⌃⌥← / →", title: "Left / Right Half", detail: "Snap front window"),
        HotKeyLegendItem(shortcut: "⌃⌥↩", title: "Maximize", detail: "Fill visible screen"),
        HotKeyLegendItem(shortcut: "⌃⌥[ / ]", title: "Thirds", detail: "Left 1/3 / Right 2/3"),
        HotKeyLegendItem(shortcut: "⌃⌥U", title: "Undo Layout", detail: "Restore previous frames"),
    ]
}
