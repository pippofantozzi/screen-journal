import CoreGraphics
import Foundation

/// Outer screen margin and inter-pane gap in points.
public struct LayoutPadding: Equatable, Codable, Sendable {
    public let outer: CGFloat
    public let gap: CGFloat

    public static let zero = LayoutPadding(outer: 0, gap: 0)

    public init(outer: CGFloat = 0, gap: CGFloat = 0) {
        self.outer = max(0, outer)
        self.gap = max(0, gap)
    }
}

/// Standard and specialized placement slots within a display's usable visible frame.
public enum SnapSlot: Equatable, Sendable {
    case leftHalf
    case rightHalf
    case maximize
    case leftThird
    case rightTwoThirds
    case rightThird
    case leftTwoThirds
    case centeredCard(widthRatio: CGFloat, heightRatio: CGFloat)
    case customHorizontal(xFraction: CGFloat, widthFraction: CGFloat)
    case rightDrawer(widthFraction: CGFloat, minWidth: CGFloat)
}

/// Coordinate conversions between AppKit's bottom-left screen space and Quartz/AX's top-left screen space.
public enum DisplayGeometry {
    /// Converts a rectangle from AppKit global coordinates (origin bottom-left of primary screen)
    /// into Accessibility / CoreGraphics coordinates (origin top-left of primary screen).
    public static func appKitToAX(rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - (rect.origin.y + rect.size.height),
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Converts a rectangle from Accessibility / CoreGraphics coordinates back into AppKit global coordinates.
    public static func axToAppKit(rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - (rect.origin.y + rect.size.height),
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

/// Pure screen geometry calculations in AX (top-left origin) coordinate space.
public enum ScreenGeometry {
    /// Computes the pixel-aligned target frame for `slot` inside `visibleFrame`.
    /// When `constraint` enforces a larger width than requested, right-anchored slots expand leftward
    /// so they stay flush with the right edge and never clip off-screen.
    public static func frame(
        for slot: SnapSlot,
        in visibleFrame: CGRect,
        constraint: AppConstraint? = nil,
        padding: LayoutPadding = .zero
    ) -> CGRect {
        let usable = insetRect(visibleFrame, by: padding.outer)
        guard usable.width > 0, usable.height > 0 else { return visibleFrame }

        let minW = constraint?.effectiveMinWidth(forScreenWidth: usable.width) ?? 0

        switch slot {
        case .maximize:
            return rounded(usable)

        case .leftHalf:
            let rawW = (usable.width - padding.gap) * 0.5
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.minX, y: usable.minY, width: width, height: usable.height))

        case .rightHalf:
            let rawW = (usable.width - padding.gap) * 0.5
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height))

        case .leftThird:
            let rawW = (usable.width - padding.gap) / 3.0
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.minX, y: usable.minY, width: width, height: usable.height))

        case .rightTwoThirds:
            let rawW = (usable.width - padding.gap) * (2.0 / 3.0)
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height))

        case .rightThird:
            let rawW = (usable.width - padding.gap) / 3.0
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height))

        case .leftTwoThirds:
            let rawW = (usable.width - padding.gap) * (2.0 / 3.0)
            let width = clampWidth(rawW, minWidth: minW, maxWidth: usable.width)
            return rounded(CGRect(x: usable.minX, y: usable.minY, width: width, height: usable.height))

        case let .centeredCard(widthRatio, heightRatio):
            let clampedWR = min(max(widthRatio, 0.1), 1.0)
            let clampedHR = min(max(heightRatio, 0.1), 1.0)
            let width = clampWidth(usable.width * clampedWR, minWidth: minW, maxWidth: usable.width)
            let height = usable.height * clampedHR
            let x = usable.minX + (usable.width - width) * 0.5
            let y = usable.minY + (usable.height - height) * 0.5
            return rounded(CGRect(x: x, y: y, width: width, height: height))

        case let .customHorizontal(xFraction, widthFraction):
            let clampedX = min(max(xFraction, 0), 1)
            let clampedWF = min(max(widthFraction, 0.05), 1)
            let width = clampWidth(usable.width * clampedWF, minWidth: minW, maxWidth: usable.width)
            let rawX = usable.minX + usable.width * clampedX
            let x = min(rawX, usable.maxX - width)
            return rounded(CGRect(x: max(usable.minX, x), y: usable.minY, width: width, height: usable.height))

        case let .rightDrawer(widthFraction, slotMinWidth):
            let clampedWF = min(max(widthFraction, 0.1), 1.0)
            let effectiveMin = max(minW, slotMinWidth)
            let width = clampWidth(usable.width * clampedWF, minWidth: effectiveMin, maxWidth: usable.width)
            return rounded(CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height))
        }
    }

    /// Splits `visibleFrame` into a non-overlapping left + right pair while respecting both apps' minimum widths.
    public static func horizontalPair(
        leftFraction: CGFloat,
        in visibleFrame: CGRect,
        leftConstraint: AppConstraint? = nil,
        rightConstraint: AppConstraint? = nil,
        padding: LayoutPadding = .zero
    ) -> (left: CGRect, right: CGRect) {
        let usable = insetRect(visibleFrame, by: padding.outer)
        guard usable.width > 0, usable.height > 0 else { return (visibleFrame, visibleFrame) }

        let availableWidth = max(0, usable.width - padding.gap)
        let clampedLeftFrac = min(max(leftFraction, 0.1), 0.9)

        let desiredRight = availableWidth * (1.0 - clampedLeftFrac)
        let rightMin = rightConstraint?.effectiveMinWidth(forScreenWidth: usable.width) ?? 0
        let leftMin = leftConstraint?.effectiveMinWidth(forScreenWidth: usable.width) ?? 0

        var rightWidth = min(availableWidth, max(desiredRight, rightMin))
        var leftWidth = availableWidth - rightWidth

        if leftWidth < leftMin && (availableWidth - leftMin) >= rightMin {
            leftWidth = leftMin
            rightWidth = availableWidth - leftWidth
        } else if leftWidth < 0 {
            leftWidth = 0
        }

        let minX = usable.minX.rounded()
        let minY = usable.minY.rounded()
        let maxX = usable.maxX.rounded()
        let height = usable.height.rounded()
        let gap = padding.gap.rounded()

        let finalRightWidth = min(maxX - minX, rightWidth.rounded())
        let rightX = max(minX, maxX - finalRightWidth)
        let finalLeftWidth = max(0, rightX - gap - minX)

        let leftRect = CGRect(x: minX, y: minY, width: finalLeftWidth, height: height)
        let rightRect = CGRect(x: rightX, y: minY, width: maxX - rightX, height: height)
        return (left: leftRect, right: rightRect)
    }

    public static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.size.width - b.size.width) <= tolerance
            && abs(a.size.height - b.size.height) <= tolerance
    }

    public static func framesMatch(_ a: CGRect, _ b: CGRect, for app: ManagedApp) -> Bool {
        framesMatch(a, b, tolerance: app.constraint.cellTolerance)
    }

    private static func insetRect(_ rect: CGRect, by outer: CGFloat) -> CGRect {
        guard outer > 0 else { return rect }
        let dx = min(outer, rect.width * 0.25)
        let dy = min(outer, rect.height * 0.25)
        return rect.insetBy(dx: dx, dy: dy)
    }

    private static func clampWidth(_ proposed: CGFloat, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(proposed, minWidth))
    }

    private static func rounded(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x.rounded(),
            y: rect.origin.y.rounded(),
            width: rect.size.width.rounded(),
            height: rect.size.height.rounded()
        )
    }
}
