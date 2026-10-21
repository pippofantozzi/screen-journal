import AppKit
import ServiceManagement

/// Screen Recording permission, login item, relaunch.
enum SystemAccess {
    static var hasScreenAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds the app to the Screen Recording list (first call shows the system prompt), then opens the pane.
    static func requestScreenAccess() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func enableOpenAtLogin() throws {
        if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
    }

    /// Screen Recording grants often only apply to a fresh process.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
