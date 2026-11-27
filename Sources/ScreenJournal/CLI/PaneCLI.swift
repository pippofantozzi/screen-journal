import AppKit
import Foundation
import PaneCore

/// CLI bridge for `ScreenJournal pane <send|dev|swap-browser|dual-browser|grok|undo|snap|summon|status>`.
enum PaneCLI {
    static func run(arguments: [String]) -> Int32 {
        switch PaneCLIParser.parse(subcommandArguments: arguments) {
        case .success(.help(let usage)):
            print(usage)
            return 0
        case .success(.status(let asJSON)):
            return printStatus(asJSON: asJSON)
        case .success(.action(let action)):
            return sendAction(action)
        case .failure(let error):
            FileHandle.standardError.write(Data("Error: \(error.message)\n".utf8))
            return 2
        }
    }

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? RunningApp.bundleID
    }

    private static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private static func loadStatus() -> PaneStatus? {
        guard let data = try? Data(contentsOf: PaneIPC.statusFileURL) else { return nil }
        return try? PaneStatus.decode(data)
    }

    private static func printStatus(asJSON: Bool) -> Int32 {
        let running = runningApp()
        let status = loadStatus()

        if asJSON {
            if let status, running != nil, let data = try? PaneStatus.encode(status),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                return 0
            }
            print("""
            {
              "running": false,
              "bundleID": "\(bundleID)"
            }
            """)
            return running == nil ? 1 : 0
        }

        guard let running else {
            print("Screen Journal: not running")
            print("Launch: open -a ScreenJournal")
            return 1
        }

        guard let status else {
            print("Screen Journal: running (PID \(running.processIdentifier)), awaiting window manager status…")
            return 0
        }

        print("Screen Journal Window Manager: \(status.enabled ? "enabled" : "disabled") (PID \(running.processIdentifier))")
        print("Accessibility: \(status.accessibilityTrusted ? "granted" : "NOT GRANTED — allow in Settings → Windows")")
        print("Profile: \(status.profile.summary)")
        print("Right browser: \(status.activeRightBrowser.displayName)")
        print("Hotkeys: \(status.registeredHotKeys) registered\(status.failedHotKeys.isEmpty ? "" : " (failed: \(status.failedHotKeys.joined(separator: ", ")))")")
        if status.dropAndSendActive { print("Active overlay: Drop & Send (⌃⌥W to restore)") }
        if status.grokDrawerActive { print("Active overlay: Grok Bot Drawer (⌃⌥G to hide)") }
        print("Undo stack: \(status.undoDepth)")
        if let last = status.lastAction {
            print("Last action: \(last)")
        }
        return 0
    }

    private static func sendAction(_ action: PaneAction) -> Int32 {
        guard runningApp() != nil else {
            FileHandle.standardError.write(Data("Screen Journal is not running. Launch it first: open -a ScreenJournal\n".utf8))
            return 1
        }

        let requestID = UUID().uuidString
        let center = DistributedNotificationCenter.default()

        final class ReplyBox: @unchecked Sendable {
            var received = false
            var ok = true
            var message = ""
        }
        let box = ReplyBox()

        let observer = center.addObserver(
            forName: PaneIPC.replyNotification(for: bundleID),
            object: nil,
            queue: nil
        ) { notification in
            guard let id = notification.userInfo?[PaneIPC.requestIDKey] as? String, id == requestID else { return }
            box.ok = (notification.userInfo?[PaneIPC.okKey] as? Bool) ?? true
            box.message = (notification.userInfo?[PaneIPC.messageKey] as? String) ?? ""
            box.received = true
        }
        defer { center.removeObserver(observer) }

        center.postNotificationName(
            PaneIPC.commandNotification(for: bundleID),
            object: nil,
            userInfo: [
                PaneIPC.actionKey: action.rawValue,
                PaneIPC.requestIDKey: requestID,
            ],
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(2.5)
        while !box.received && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03))
        }

        if box.received {
            if !box.message.isEmpty {
                if box.ok {
                    print(box.message)
                } else {
                    FileHandle.standardError.write(Data("\(box.message)\n".utf8))
                }
            }
            return box.ok ? 0 : 1
        }

        print("Sent '\(action.rawValue)' to Screen Journal.")
        return 0
    }
}
