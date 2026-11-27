import CoreGraphics
import Foundation

/// A physical display described in AX (top-left origin) coordinates.
public struct DisplayDescriptor: Equatable, Codable, Sendable, Identifiable {
    public let id: UInt32
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isBuiltIn: Bool
    public let isPrimary: Bool

    public init(
        id: UInt32,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isBuiltIn: Bool,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isBuiltIn = isBuiltIn
        self.isPrimary = isPrimary
    }

    public var resolutionLabel: String {
        "\(Int(frame.width.rounded()))×\(Int(frame.height.rounded()))"
    }
}

public enum DisplayProfileKind: String, Equatable, Codable, Sendable {
    case laptopOnly = "laptop"
    case dualDisplay = "dual"

    public var label: String {
        switch self {
        case .laptopOnly: return "Laptop"
        case .dualDisplay: return "Dual Display"
        }
    }
}

/// Logical display slot used to route scenes across single- and multi-monitor setups.
public enum DisplayRole: Equatable, Sendable {
    case devWork
    case companion
}

/// Active display routing profile derived from connected displays.
public struct DisplayProfile: Equatable, Codable, Sendable {
    public let kind: DisplayProfileKind
    public let displays: [DisplayDescriptor]
    public let primaryWorkDisplay: DisplayDescriptor
    public let companionDisplay: DisplayDescriptor

    public init(
        kind: DisplayProfileKind,
        displays: [DisplayDescriptor],
        primaryWorkDisplay: DisplayDescriptor,
        companionDisplay: DisplayDescriptor
    ) {
        self.kind = kind
        self.displays = displays
        self.primaryWorkDisplay = primaryWorkDisplay
        self.companionDisplay = companionDisplay
    }

    public static func resolve(displays: [DisplayDescriptor]) -> DisplayProfile {
        guard let fallback = displays.first(where: \.isPrimary) ?? displays.first else {
            let defaultMBA = DisplayDescriptor(
                id: 1,
                name: "Built-in Retina Display",
                frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
                visibleFrame: CGRect(x: 0, y: 37, width: 1710, height: 1070),
                isBuiltIn: true,
                isPrimary: true
            )
            return DisplayProfile(
                kind: .laptopOnly,
                displays: [defaultMBA],
                primaryWorkDisplay: defaultMBA,
                companionDisplay: defaultMBA
            )
        }

        if displays.count <= 1 {
            return DisplayProfile(
                kind: .laptopOnly,
                displays: displays,
                primaryWorkDisplay: fallback,
                companionDisplay: fallback
            )
        }

        let externals = displays.filter { !$0.isBuiltIn }
        let builtIn = displays.first(where: \.isBuiltIn)

        let devDisplay: DisplayDescriptor
        let companion: DisplayDescriptor

        if let largestExternal = externals.max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }) {
            devDisplay = largestExternal
            companion = builtIn
                ?? displays.first(where: { $0.id != largestExternal.id })
                ?? largestExternal
        } else {
            devDisplay = fallback
            companion = displays.first(where: { $0.id != fallback.id }) ?? fallback
        }

        return DisplayProfile(
            kind: .dualDisplay,
            displays: displays,
            primaryWorkDisplay: devDisplay,
            companionDisplay: companion
        )
    }

    public func display(for role: DisplayRole) -> DisplayDescriptor {
        switch role {
        case .devWork: return primaryWorkDisplay
        case .companion: return companionDisplay
        }
    }

    public func display(containing rect: CGRect) -> DisplayDescriptor {
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        if let direct = displays.first(where: { $0.frame.contains(mid) }) {
            return direct
        }
        if let best = displays.max(by: {
            area($0.frame.intersection(rect)) < area($1.frame.intersection(rect))
        }), area(best.frame.intersection(rect)) > 0 {
            return best
        }
        return displays.first(where: \.isPrimary) ?? primaryWorkDisplay
    }

    public var summary: String {
        switch kind {
        case .laptopOnly:
            return "Laptop · \(primaryWorkDisplay.resolutionLabel)"
        case .dualDisplay:
            return "Dual · Ext \(primaryWorkDisplay.resolutionLabel) + Built-in \(companionDisplay.resolutionLabel)"
        }
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
