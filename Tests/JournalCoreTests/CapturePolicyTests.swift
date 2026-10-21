import Testing
@testable import JournalCore

struct CapturePolicyTests {
    let policy = CapturePolicy(idleThreshold: 120, excludedBundleIDs: ["com.1password.1password"], minChangeRatio: 0.01)
    let active = CaptureConditions(isPaused: false, isLocked: false, idleSeconds: 3, frontmostBundleID: "com.apple.Safari")

    @Test func capturesWhenActive() {
        #expect(policy.gate(active) == .capture)
    }

    @Test func pauseWinsOverEverything() {
        var c = active
        c.isPaused = true
        c.isLocked = true
        #expect(policy.gate(c) == .skip(.paused))
    }

    @Test func skipsWhenLocked() {
        var c = active
        c.isLocked = true
        #expect(policy.gate(c) == .skip(.locked))
    }

    @Test func skipsWhenIdleAtThreshold() {
        var c = active
        c.idleSeconds = 120
        #expect(policy.gate(c) == .skip(.idle))
    }

    @Test func skipsWhenExcludedAppIsFrontmost() {
        var c = active
        c.frontmostBundleID = "com.1password.1password"
        #expect(policy.gate(c) == .skip(.excludedApp))
    }

    @Test func keepsFirstFrame() {
        let sig = FrameSignature(thumbnail: .solid(10), bundleID: "a", windowTitle: "t")
        #expect(policy.decide(current: sig, previous: nil) == .keep)
    }

    @Test func unchangedWhenPixelsAndWindowMatch() {
        let sig = FrameSignature(thumbnail: .solid(10), bundleID: "a", windowTitle: "t")
        #expect(policy.decide(current: sig, previous: sig) == .unchanged)
    }

    @Test func keepsWhenWindowTitleChangesEvenIfPixelsMatch() {
        let a = FrameSignature(thumbnail: .solid(10), bundleID: "a", windowTitle: "Inbox")
        let b = FrameSignature(thumbnail: .solid(10), bundleID: "a", windowTitle: "Draft")
        #expect(policy.decide(current: b, previous: a) == .keep)
    }

    @Test func keepsWhenEnoughPixelsChange() {
        let a = FrameSignature(thumbnail: .solid(10), bundleID: "a", windowTitle: "t")
        let b = FrameSignature(thumbnail: .solid(10).painting(count: 5, value: 200), bundleID: "a", windowTitle: "t")
        #expect(policy.decide(current: b, previous: a) == .keep)
    }
}

struct ThumbnailTests {
    @Test func identicalThumbnailsHaveNoChange() {
        #expect(Thumbnail.solid(50).changeRatio(to: .solid(50)) == 0)
    }

    @Test func smallLuminanceNoiseIsIgnored() {
        #expect(Thumbnail.solid(50).changeRatio(to: .solid(55)) == 0)
    }

    @Test func countsChangedPixelsAsFraction() {
        let changed = Thumbnail.solid(50).painting(count: 10, value: 200)
        #expect(Thumbnail.solid(50).changeRatio(to: changed) == 0.1)
    }

    @Test func differentSizesAreFullyChanged() {
        let small = Thumbnail(width: 2, height: 2, luma: [0, 0, 0, 0])
        #expect(Thumbnail.solid(0).changeRatio(to: small) == 1)
    }
}

extension Thumbnail {
    /// 10×10 thumbnail of a single luminance.
    static func solid(_ value: UInt8) -> Thumbnail {
        Thumbnail(width: 10, height: 10, luma: Array(repeating: value, count: 100))
    }

    func painting(count: Int, value: UInt8) -> Thumbnail {
        var luma = self.luma
        for i in 0..<count { luma[i] = value }
        return Thumbnail(width: width, height: height, luma: luma)
    }
}
