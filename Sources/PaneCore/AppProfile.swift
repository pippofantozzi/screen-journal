import CoreGraphics
import Foundation

/// The 7 daily apps Pane is tailored for, along with their exact bundle IDs and AX quirks.
public enum ManagedApp: String, CaseIterable, Codable, Sendable, Hashable {
    case ghostty
    case zen
    case chrome
    case safari
    case grokBot = "grok-bot"
    case finder
    case whatsapp

    public var bundleID: String {
        switch self {
        case .ghostty: return "com.mitchellh.ghostty"
        case .zen: return "app.zen-browser.zen"
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .grokBot: return "com.anysphere.sand"
        case .finder: return "com.apple.finder"
        case .whatsapp: return "net.whatsapp.WhatsApp"
        }
    }

    public var displayName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .zen: return "Zen Browser"
        case .chrome: return "Google Chrome"
        case .safari: return "Safari"
        case .grokBot: return "Grok Bot"
        case .finder: return "Finder"
        case .whatsapp: return "WhatsApp"
        }
    }

    public var mnemonicKey: String {
        switch self {
        case .ghostty: return "T"
        case .zen: return "Z"
        case .chrome: return "C"
        case .safari: return "S"
        case .grokBot: return "G"
        case .finder: return "F"
        case .whatsapp: return "W"
        }
    }

    /// Ordered browser rotation for Dev Split right-pane swapping (⌃⌥B).
    public static let browsers: [ManagedApp] = [.zen, .chrome, .safari]

    public var isBrowser: Bool {
        Self.browsers.contains(self)
    }

    public var constraint: AppConstraint {
        switch self {
        case .whatsapp:
            // Mac Catalyst enforces a wide minimum width (~640-720px) and animates slowly unless AXEnhancedUserInterface is toggled off.
            return AppConstraint(
                minWidth: 680,
                minWidthFraction: 0.58,
                cellTolerance: 6,
                disableEnhancedUIOnMove: true,
                needsPositionSizePosition: false,
                autoOpenDownloadsIfEmpty: false
            )
        case .grokBot:
            // Electron enforces ~450-500px min-width and benefits from disabling AXEnhancedUserInterface during move/resize.
            return AppConstraint(
                minWidth: 500,
                minWidthFraction: nil,
                cellTolerance: 6,
                disableEnhancedUIOnMove: true,
                needsPositionSizePosition: false,
                autoOpenDownloadsIfEmpty: false
            )
        case .ghostty:
            // Terminal window dimensions snap to character cell multiples; allow ±1 cell tolerance when verifying geometry.
            return AppConstraint(
                minWidth: 360,
                minWidthFraction: nil,
                cellTolerance: 24,
                disableEnhancedUIOnMove: false,
                needsPositionSizePosition: false,
                autoOpenDownloadsIfEmpty: false
            )
        case .zen:
            // Gecko/Firefox can clip when moving across displays unless Position -> Size -> Position is applied.
            return AppConstraint(
                minWidth: 420,
                minWidthFraction: nil,
                cellTolerance: 4,
                disableEnhancedUIOnMove: false,
                needsPositionSizePosition: true,
                autoOpenDownloadsIfEmpty: false
            )
        case .finder:
            return AppConstraint(
                minWidth: 360,
                minWidthFraction: nil,
                cellTolerance: 4,
                disableEnhancedUIOnMove: false,
                needsPositionSizePosition: false,
                autoOpenDownloadsIfEmpty: true
            )
        case .chrome, .safari:
            return AppConstraint(
                minWidth: 400,
                minWidthFraction: nil,
                cellTolerance: 4,
                disableEnhancedUIOnMove: false,
                needsPositionSizePosition: false,
                autoOpenDownloadsIfEmpty: false
            )
        }
    }

    public static func from(bundleID: String?) -> ManagedApp? {
        guard let bundleID else { return nil }
        return Self.allCases.first { $0.bundleID == bundleID }
    }

    public static func from(cliName: String) -> ManagedApp? {
        switch cliName.lowercased() {
        case "ghostty", "terminal", "t": return .ghostty
        case "zen", "z": return .zen
        case "chrome", "google-chrome", "c": return .chrome
        case "safari", "s": return .safari
        case "grok", "grok-bot", "grokbot", "g": return .grokBot
        case "finder", "f": return .finder
        case "whatsapp", "wa", "w": return .whatsapp
        default: return nil
        }
    }
}

/// Per-app geometry clamps and Accessibility quirk flags.
public struct AppConstraint: Equatable, Codable, Sendable {
    public let minWidth: CGFloat
    public let minWidthFraction: CGFloat?
    public let cellTolerance: CGFloat
    public let disableEnhancedUIOnMove: Bool
    public let needsPositionSizePosition: Bool
    public let autoOpenDownloadsIfEmpty: Bool

    public static let standard = AppConstraint(
        minWidth: 320,
        minWidthFraction: nil,
        cellTolerance: 4,
        disableEnhancedUIOnMove: false,
        needsPositionSizePosition: false,
        autoOpenDownloadsIfEmpty: false
    )

    public init(
        minWidth: CGFloat = 320,
        minWidthFraction: CGFloat? = nil,
        cellTolerance: CGFloat = 4,
        disableEnhancedUIOnMove: Bool = false,
        needsPositionSizePosition: Bool = false,
        autoOpenDownloadsIfEmpty: Bool = false
    ) {
        self.minWidth = minWidth
        self.minWidthFraction = minWidthFraction
        self.cellTolerance = cellTolerance
        self.disableEnhancedUIOnMove = disableEnhancedUIOnMove
        self.needsPositionSizePosition = needsPositionSizePosition
        self.autoOpenDownloadsIfEmpty = autoOpenDownloadsIfEmpty
    }

    public static func forBundleID(_ bundleID: String?) -> AppConstraint {
        ManagedApp.from(bundleID: bundleID)?.constraint ?? .standard
    }

    /// Minimum width in points for a window on a screen of the given usable width.
    public func effectiveMinWidth(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        let fractional = minWidthFraction.map { ceil(screenWidth * $0) } ?? 0
        return min(screenWidth, max(minWidth, fractional))
    }
}
