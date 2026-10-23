import AppKit

/// The menu bar app, seen from the command line: quit it before rewriting the journal, reopen it after.
struct RunningApp {
    static let bundleID = "com.filippofantozzi.ScreenJournal"

    /// Another copy is already recording; a second would write every frame twice.
    static var anotherIsRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { $0.processIdentifier != getpid() }
    }

    /// Quits a running copy and returns where it was launched from, or nil when it wasn't running.
    static func quit() -> URL? {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != getpid() }
        guard let app = others.first else { return nil }
        let url = app.bundleURL
        for app in others { app.terminate() }
        if !waitForExit(others, seconds: 10) {
            for app in others { app.forceTerminate() }
            _ = waitForExit(others, seconds: 5)
        }
        return url
    }

    static func reopen(_ url: URL) {
        let done = DispatchSemaphore(value: 0)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in done.signal() }
        done.wait()
    }

    /// Polls the process table: without a run loop `isTerminated` never updates.
    private static func waitForExit(_ apps: [NSRunningApplication], seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if apps.allSatisfy({ kill($0.processIdentifier, 0) != 0 }) { return true }
            usleep(100_000)
        }
        return false
    }
}
