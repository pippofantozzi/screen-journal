import CoreGraphics
import Testing
@testable import PaneCore

struct DisplayAndSceneTests {
    private let builtInMBA = DisplayDescriptor(
        id: 1,
        name: "Built-in Retina Display",
        frame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
        visibleFrame: CGRect(x: 0, y: 37, width: 1710, height: 1070),
        isBuiltIn: true,
        isPrimary: true
    )

    private let external1080p = DisplayDescriptor(
        id: 2,
        name: "External Monitor",
        frame: CGRect(x: 1710, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1710, y: 25, width: 1920, height: 1055),
        isBuiltIn: false,
        isPrimary: false
    )

    @Test func laptopOnlyProfileUsesBuiltInForAllRoles() {
        let profile = DisplayProfile.resolve(displays: [builtInMBA])
        #expect(profile.kind == .laptopOnly)
        #expect(profile.display(for: .devWork) == builtInMBA)
        #expect(profile.display(for: .companion) == builtInMBA)
    }

    @Test func dualDisplayRoutesDevToExternalAndCompanionsToBuiltIn() {
        let profile = DisplayProfile.resolve(displays: [builtInMBA, external1080p])
        #expect(profile.kind == .dualDisplay)
        #expect(profile.display(for: .devWork) == external1080p)
        #expect(profile.display(for: .companion) == builtInMBA)

        let devPlan = ScenePlanner.devSplit(profile: profile, browser: .zen)
        #expect(devPlan.targets.count == 2)
        #expect(devPlan.targets[0].app == .ghostty)
        #expect(devPlan.targets[0].displayID == external1080p.id)
        #expect(devPlan.targets[1].app == .zen)
        #expect(devPlan.targets[1].displayID == external1080p.id)
        #expect(devPlan.targets[0].frame.minX == 1710)
        #expect(devPlan.targets[1].frame.maxX == external1080p.visibleFrame.maxX)
        #expect(devPlan.targets[0].frame.maxX == devPlan.targets[1].frame.minX)

        let dualBrowserPlan = ScenePlanner.dualBrowser(profile: profile, rightBrowser: .safari)
        #expect(dualBrowserPlan.targets[0].app == .zen)
        #expect(dualBrowserPlan.targets[1].app == .safari)
        #expect(dualBrowserPlan.targets[0].frame.width == 960)
        #expect(dualBrowserPlan.targets[1].frame.width == 960)
        #expect(dualBrowserPlan.targets[1].displayID == external1080p.id)

        let sendPlan = ScenePlanner.dropAndSend(profile: profile)
        #expect(sendPlan.targets[0].app == .finder)
        #expect(sendPlan.targets[0].displayID == builtInMBA.id)
        #expect(sendPlan.targets[0].autoOpenDownloadsIfEmpty == true)
        #expect(sendPlan.targets[1].app == .whatsapp)
        #expect(sendPlan.targets[1].displayID == builtInMBA.id)
        #expect(sendPlan.targets[1].frame.width >= 992)

        let grokPlan = ScenePlanner.grokDrawer(profile: profile)
        #expect(grokPlan.targets[0].app == .grokBot)
        #expect(grokPlan.targets[0].displayID == builtInMBA.id)
        #expect(grokPlan.targets[0].frame.width >= 500)
    }

    @Test func browserSwapCyclesAndSkipsUninstalledBrowsers() {
        let profile = DisplayProfile.resolve(displays: [builtInMBA])
        let s1 = ScenePlanner.swapRightBrowser(profile: profile, currentBrowser: .zen)
        #expect(s1.nextBrowser == .chrome)
        let s2 = ScenePlanner.swapRightBrowser(profile: profile, currentBrowser: s1.nextBrowser)
        #expect(s2.nextBrowser == .safari)
        let s3 = ScenePlanner.swapRightBrowser(profile: profile, currentBrowser: s2.nextBrowser)
        #expect(s3.nextBrowser == .zen)

        // On another Mac without Zen installed, cycle cleanly between Chrome and Safari.
        let installed: Set<ManagedApp> = [.chrome, .safari, .finder, .whatsapp]
        #expect(ScenePlanner.nextRightBrowser(after: .zen, installedApps: installed) == .chrome)
        #expect(ScenePlanner.nextRightBrowser(after: .chrome, installedApps: installed) == .safari)
        #expect(ScenePlanner.nextRightBrowser(after: .safari, installedApps: installed) == .chrome)
    }

    @Test func activeBrowserAndDualBrowserSelection() {
        let running: Set<String> = [ManagedApp.ghostty.bundleID, ManagedApp.safari.bundleID]
        #expect(ScenePlanner.activeBrowser(frontmostBundleID: ManagedApp.chrome.bundleID, runningBundleIDs: running) == .chrome)
        #expect(ScenePlanner.activeBrowser(frontmostBundleID: ManagedApp.ghostty.bundleID, lastRightBrowser: .zen, runningBundleIDs: running) == .safari)

        #expect(ScenePlanner.dualBrowserRight(runningBundleIDs: running) == .safari)
        #expect(ScenePlanner.dualBrowserRight(runningBundleIDs: [ManagedApp.chrome.bundleID, ManagedApp.safari.bundleID]) == .chrome)
        #expect(ScenePlanner.dualBrowserRight(runningBundleIDs: [], installedApps: [.safari]) == .safari)
    }

    @Test func summonDecisionCoversUnavailableLaunchActivateCycleAndHide() {
        #expect(ScenePlanner.summonDecision(for: .ghostty, isInstalled: false, isRunning: false, isFrontmost: false, standardWindowCount: 0) == .unavailable(.ghostty))
        #expect(ScenePlanner.summonDecision(for: .ghostty, isInstalled: true, isRunning: false, isFrontmost: false, standardWindowCount: 0) == .launch(.ghostty))
        #expect(ScenePlanner.summonDecision(for: .finder, isInstalled: true, isRunning: true, isFrontmost: false, standardWindowCount: 0) == .activate(.finder, autoOpenDownloadsIfEmpty: true))
        #expect(ScenePlanner.summonDecision(for: .zen, isInstalled: true, isRunning: true, isFrontmost: true, standardWindowCount: 3) == .cycleWindows(.zen))
        #expect(ScenePlanner.summonDecision(for: .ghostty, isInstalled: true, isRunning: true, isFrontmost: true, standardWindowCount: 1) == .hideAndRestorePrevious(.ghostty))
    }

    @Test func appBundleIDsAndAXQuirkFlagsMatchSpec() {
        #expect(ManagedApp.ghostty.bundleID == "com.mitchellh.ghostty")
        #expect(ManagedApp.zen.bundleID == "app.zen-browser.zen")
        #expect(ManagedApp.chrome.bundleID == "com.google.Chrome")
        #expect(ManagedApp.safari.bundleID == "com.apple.Safari")
        #expect(ManagedApp.grokBot.bundleID == "com.anysphere.sand")
        #expect(ManagedApp.finder.bundleID == "com.apple.finder")
        #expect(ManagedApp.whatsapp.bundleID == "net.whatsapp.WhatsApp")

        #expect(ManagedApp.whatsapp.constraint.disableEnhancedUIOnMove == true)
        #expect(ManagedApp.grokBot.constraint.disableEnhancedUIOnMove == true)
        #expect(ManagedApp.zen.constraint.needsPositionSizePosition == true)
        #expect(ManagedApp.finder.constraint.autoOpenDownloadsIfEmpty == true)
        #expect(ManagedApp.ghostty.constraint.cellTolerance >= 20)
    }
}
