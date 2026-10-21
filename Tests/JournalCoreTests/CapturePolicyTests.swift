import Foundation
import Testing
@testable import JournalCore

struct CapturePolicyTests {
    let policy = CapturePolicy(idleThreshold: 120, excludedBundleIDs: ["com.1password.1password"], minChangeRatio: 0.01)
    let active = CaptureConditions(isPaused: false, isLocked: false, idleSeconds: 3,
                                   frontmostBundleID: "com.apple.Safari", frontmostWindowTitle: "Docs")

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

    @Test func skipsPrivateBrowsingWindowsCaseInsensitively() {
        var c = active
        c.frontmostWindowTitle = "GitHub — incognito"
        #expect(policy.gate(c) == .skip(.privateWindow))
    }

    @Test func excludedAppWinsOverPrivateWindow() {
        var c = active
        c.frontmostBundleID = "com.1password.1password"
        c.frontmostWindowTitle = "Private Browsing"
        #expect(policy.gate(c) == .skip(.excludedApp))
    }

    @Test func privateWindowOpensSkippedGap() {
        #expect(SkipReason.privateWindow.eventKind == .skipped)
    }
}

struct FrameDecisionTests {
    let policy = CapturePolicy(minChangeRatio: 0.01, bigChangeRatio: 0.15, imageInterval: 60)
    let now = Date(timeIntervalSince1970: 1_000)

    static func sig(_ thumbnail: Thumbnail = .solid(10), app: String = "a", title: String = "t") -> FrameSignature {
        FrameSignature(thumbnail: thumbnail, bundleID: app, windowTitle: title)
    }

    static let small = Thumbnail.solid(10).painting(count: 5, value: 200)
    static let big = Thumbnail.solid(10).painting(count: 15, value: 200)

    @Test(arguments: [
        // (name, current, previous, seconds since last image, expected)
        ("first frame", Self.sig(), nil, nil, FrameDecision.record(saveImage: true)),
        ("app changed", Self.sig(app: "b"), Self.sig(), 1, .record(saveImage: true)),
        ("title changed", Self.sig(title: "Draft"), Self.sig(), 1, .record(saveImage: true)),
        ("pixels identical", Self.sig(), Self.sig(), 1000, .unchanged),
        ("big change", Self.sig(big), Self.sig(), 1, .record(saveImage: true)),
        ("small change, image stale", Self.sig(small), Self.sig(), 60, .record(saveImage: true)),
        ("small change, no image yet", Self.sig(small), Self.sig(), nil, .record(saveImage: true)),
        ("small change, image fresh", Self.sig(small), Self.sig(), 59, .record(saveImage: false)),
    ] as [(String, FrameSignature, FrameSignature?, TimeInterval?, FrameDecision)])
    func decides(_ name: String, current: FrameSignature, previous: FrameSignature?, sinceImage: TimeInterval?, expected: FrameDecision) {
        let lastImageAt = sinceImage.map { now - $0 }
        #expect(policy.decide(current: current, previous: previous, lastImageAt: lastImageAt, now: now) == expected, "\(name)")
    }
}

struct FreshImageTests {
    let policy = CapturePolicy(freshImageLines: 10)

    @Test(arguments: [
        (true, 0, true),
        (false, 9, false),
        (false, 10, true),
        (false, 53, true),
    ])
    func savesWhenLotsOfTextAppears(saveImage: Bool, newLineCount: Int, expected: Bool) {
        #expect(policy.needsFreshImage(decided: saveImage, newLineCount: newLineCount) == expected)
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
