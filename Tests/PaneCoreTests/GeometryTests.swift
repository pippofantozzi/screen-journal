import CoreGraphics
import Testing
@testable import PaneCore

struct GeometryTests {
    private let mbaVisible = CGRect(x: 0, y: 37, width: 1710, height: 1070)

    @Test func standardHalvesAndMaximize() {
        let left = ScreenGeometry.frame(for: .leftHalf, in: mbaVisible)
        let right = ScreenGeometry.frame(for: .rightHalf, in: mbaVisible)
        let maxRect = ScreenGeometry.frame(for: .maximize, in: mbaVisible)

        #expect(left == CGRect(x: 0, y: 37, width: 855, height: 1070))
        #expect(right == CGRect(x: 855, y: 37, width: 855, height: 1070))
        #expect(left.maxX == right.minX)
        #expect(maxRect == mbaVisible)
    }

    @Test func thirdsAndCenteredCardWithPadding() {
        let padding = LayoutPadding(outer: 10, gap: 10)
        let leftThird = ScreenGeometry.frame(for: .leftThird, in: mbaVisible, padding: padding)
        let rightTwoThirds = ScreenGeometry.frame(for: .rightTwoThirds, in: mbaVisible, padding: padding)

        #expect(leftThird.origin == CGPoint(x: 10, y: 47))
        #expect(leftThird.width == 560)
        #expect(rightTwoThirds.width == 1120)
        #expect(rightTwoThirds.maxX == 1700)
        #expect(rightTwoThirds.minX - leftThird.maxX == 10)

        let card = ScreenGeometry.frame(for: .centeredCard(widthRatio: 0.65, heightRatio: 0.75), in: mbaVisible)
        #expect(abs(card.midX - mbaVisible.midX) <= 1)
        #expect(abs(card.midY - mbaVisible.midY) <= 1)
        #expect(card.width == 1112)
    }

    @Test func customHorizontalClampsInsideScreen() {
        let rect = ScreenGeometry.frame(
            for: .customHorizontal(xFraction: 0.8, widthFraction: 0.4),
            in: mbaVisible
        )
        #expect(rect.maxX <= mbaVisible.maxX)
        #expect(rect.minX >= mbaVisible.minX)
    }

    @Test func whatsappClampedAtLeast58PercentAnd680px() {
        let pairMBA = ScreenGeometry.horizontalPair(
            leftFraction: 0.42,
            in: mbaVisible,
            leftConstraint: ManagedApp.finder.constraint,
            rightConstraint: ManagedApp.whatsapp.constraint
        )
        #expect(pairMBA.right.width >= ceil(1710 * 0.58))
        #expect(pairMBA.right.width >= 680)
        #expect(pairMBA.left.maxX == pairMBA.right.minX)
        #expect(pairMBA.right.maxX == mbaVisible.maxX)

        let narrow = CGRect(x: 0, y: 37, width: 1024, height: 700)
        let pairNarrow = ScreenGeometry.horizontalPair(
            leftFraction: 0.42,
            in: narrow,
            leftConstraint: ManagedApp.finder.constraint,
            rightConstraint: ManagedApp.whatsapp.constraint
        )
        #expect(pairNarrow.right.width == 680)
        #expect(pairNarrow.right.maxX == 1024)
        #expect(pairNarrow.left.width == 344)
        #expect(pairNarrow.left.maxX == pairNarrow.right.minX)
    }

    @Test func grokDrawerClampedAtLeast500pxForElectron() {
        let mbaDrawer = ScreenGeometry.frame(
            for: .rightDrawer(widthFraction: 0.38, minWidth: 500),
            in: mbaVisible,
            constraint: ManagedApp.grokBot.constraint
        )
        #expect(mbaDrawer.width == 650)
        #expect(mbaDrawer.maxX == mbaVisible.maxX)

        let smallExt = CGRect(x: 1710, y: 25, width: 1280, height: 695)
        let smallDrawer = ScreenGeometry.frame(
            for: .rightDrawer(widthFraction: 0.38, minWidth: 500),
            in: smallExt,
            constraint: ManagedApp.grokBot.constraint
        )
        #expect(smallDrawer.width == 500)
        #expect(smallDrawer.maxX == smallExt.maxX)
        #expect(smallDrawer.minX == smallExt.maxX - 500)
    }

    @Test func ghosttyCellSizeToleranceVerification() {
        let target = CGRect(x: 0, y: 37, width: 821, height: 1070)
        let snappedToCell = CGRect(x: 0, y: 37, width: 804, height: 1056)
        #expect(ScreenGeometry.framesMatch(target, snappedToCell, for: .ghostty))
        #expect(!ScreenGeometry.framesMatch(target, snappedToCell, for: .safari))
    }

    @Test func appKitToAXCoordinateConversionRoundTrips() {
        let primaryHeight: CGFloat = 1107
        let appKitPrimary = CGRect(x: 0, y: 0, width: 1710, height: 1070)
        let axPrimary = DisplayGeometry.appKitToAX(rect: appKitPrimary, primaryScreenHeight: primaryHeight)
        #expect(axPrimary == CGRect(x: 0, y: 37, width: 1710, height: 1070))
        #expect(DisplayGeometry.axToAppKit(rect: axPrimary, primaryScreenHeight: primaryHeight) == appKitPrimary)

        let appKitAbove = CGRect(x: 0, y: 1107, width: 1920, height: 1055)
        let axAbove = DisplayGeometry.appKitToAX(rect: appKitAbove, primaryScreenHeight: primaryHeight)
        #expect(axAbove == CGRect(x: 0, y: -1055, width: 1920, height: 1055))
        #expect(DisplayGeometry.axToAppKit(rect: axAbove, primaryScreenHeight: primaryHeight) == appKitAbove)
    }
}
