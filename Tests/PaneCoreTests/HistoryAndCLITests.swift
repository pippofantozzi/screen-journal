import CoreGraphics
import Foundation
import Testing
@testable import PaneCore

struct HistoryAndCLITests {
    private func snapshot(_ reason: String, front: String, frame: CGRect) -> LayoutSnapshot {
        LayoutSnapshot(
            reason: reason,
            previousFrontmostBundleID: front,
            windows: [
                WindowSnapshot(bundleID: front, pid: 100, windowTitle: "Main", windowIndex: 0, frame: frame),
            ]
        )
    }

    @Test func dropAndSendToggleActivatesThenDismissesWithSavedFrames() {
        var history = LayoutHistory()
        let saved = snapshot("Drop & Send", front: ManagedApp.ghostty.bundleID, frame: CGRect(x: 0, y: 37, width: 820, height: 1070))

        let first = history.toggleOverlay(.dropAndSend, overlayVisible: false) { saved }
        #expect(first == .activate(.dropAndSend))
        #expect(history.isDropAndSendActive == true)
        #expect(history.undoStack.count == 1)

        let second = history.toggleOverlay(.dropAndSend, overlayVisible: true) {
            Issue.record("Should not recapture snapshot when dismissing active overlay")
            return saved
        }
        #expect(second == .dismiss(.dropAndSend, snapshot: saved, appsToHide: [.finder, .whatsapp]))
        #expect(history.isDropAndSendActive == false)
    }

    @Test func grokDrawerToggleReopensIfManuallyHidden() {
        var history = LayoutHistory()
        let snap1 = snapshot("Grok", front: ManagedApp.zen.bundleID, frame: CGRect(x: 0, y: 37, width: 1710, height: 1070))
        _ = history.toggleOverlay(.grokDrawer, overlayVisible: false) { snap1 }
        #expect(history.isGrokDrawerActive == true)

        let snap2 = snapshot("Grok 2", front: ManagedApp.ghostty.bundleID, frame: CGRect(x: 0, y: 37, width: 820, height: 1070))
        let next = history.toggleOverlay(.grokDrawer, overlayVisible: false) { snap2 }
        #expect(next == .activate(.grokDrawer))
        #expect(history.activeOverlaySnapshot == snap2)

        let dismiss = history.toggleOverlay(.grokDrawer, overlayVisible: true) { snap2 }
        #expect(dismiss == .dismiss(.grokDrawer, snapshot: snap2, appsToHide: [.grokBot]))
    }

    @Test func undoStackRespectsCapacityAndClearsOverlayState() {
        var history = LayoutHistory(capacity: 2)
        let s1 = snapshot("1", front: "a", frame: .zero)
        let s2 = snapshot("2", front: "b", frame: .zero)
        let s3 = snapshot("3", front: "c", frame: .zero)

        history.recordAction(s1)
        history.recordAction(s2)
        history.recordAction(s3)
        #expect(history.undoStack.count == 2)
        #expect(history.popUndo() == s3)
        #expect(history.popUndo() == s2)
        #expect(history.popUndo() == nil)
    }

    @Test func cliParserHandlesAllCommandsAndErrors() {
        #expect(PaneCLIParser.parse(subcommandArguments: ["send"]) == .success(.action(.send)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["dev"]) == .success(.action(.dev)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["swap-browser"]) == .success(.action(.swapBrowser)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["dual-browser"]) == .success(.action(.dualBrowser)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["grok"]) == .success(.action(.grok)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["undo"]) == .success(.action(.undo)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["snap", "left"]) == .success(.action(.snapLeft)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["snap", "right"]) == .success(.action(.snapRight)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["snap", "max"]) == .success(.action(.snapMax)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["snap", "left-third"]) == .success(.action(.snapLeftThird)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["snap", "right-two-thirds"]) == .success(.action(.snapRightTwoThirds)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["summon", "ghostty"]) == .success(.action(.summonGhostty)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["status"]) == .success(.status(json: false)))
        #expect(PaneCLIParser.parse(subcommandArguments: ["status", "--json"]) == .success(.status(json: true)))

        if case .failure = PaneCLIParser.parse(subcommandArguments: ["snap", "bogus"]) {
            // expected
        } else {
            Issue.record("Expected failure for bogus snap slot")
        }

        if case .failure = PaneCLIParser.parse(subcommandArguments: ["unknown"]) {
            // expected
        } else {
            Issue.record("Expected failure for unknown command")
        }
    }

    @Test func ipcChannelScopedToBundleIDAndStatusRoundTrips() throws {
        #expect(PaneIPC.commandNotification(for: "com.filippofantozzi.ScreenJournal").rawValue == "com.filippofantozzi.ScreenJournal.pane.command")
        #expect(PaneIPC.replyNotification(for: "com.filippofantozzi.ScreenJournal").rawValue == "com.filippofantozzi.ScreenJournal.pane.reply")

        let profile = DisplayProfile.resolve(displays: [])
        let status = PaneStatus(
            pid: 4242,
            enabled: true,
            accessibilityTrusted: true,
            profile: profile,
            activeRightBrowser: .zen,
            dropAndSendActive: false,
            grokDrawerActive: true,
            undoDepth: 3,
            registeredHotKeys: 16,
            failedHotKeys: [],
            lastAction: "Grok Bot Drawer",
            updatedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let data = try PaneStatus.encode(status)
        let decoded = try PaneStatus.decode(data)
        #expect(decoded == status)
    }
}
