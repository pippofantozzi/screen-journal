import AppKit
import Foundation
import JournalCore

/// CLI bridge for `ScreenJournal awake <start|extend|stop|status|backstop>`.
enum AwakeCLI {
    static func run(arguments: [String]) -> Int32 {
        switch AwakeCLIParser.parse(subcommandArguments: arguments) {
        case .success(.help(let usage)):
            print(usage)
            return 0
        case .success(.start(let seconds)):
            return sendCommand(action: "start", seconds: seconds)
        case .success(.extend(let seconds)):
            return sendCommand(action: "extend", seconds: seconds)
        case .success(.stop):
            return sendCommand(action: "stop", seconds: nil)
        case .success(.status(let asJSON)):
            return printStatus(asJSON: asJSON)
        case .success(.backstop):
            return runBackstop()
        case .failure(let error):
            FileHandle.standardError.write(Data("Error: \(error.message)\n".utf8))
            return 2
        }
    }

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? RunningApp.bundleID
    }

    private static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != getpid() }
    }

    private static func printStatus(asJSON: Bool) -> Int32 {
        let running = runningApp()
        let status = AwakeStore.readStatus()

        if asJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let status, running != nil, let data = try? encoder.encode(status),
               let text = String(data: data, encoding: .utf8) {
                print(text)
                return 0
            }
            print("{\n  \"running\": false,\n  \"active\": false\n}")
            return running == nil ? 1 : 0
        }

        guard let running else {
            print("Screen Journal: not running")
            return 1
        }
        guard let status else {
            print("Screen Journal: running (PID \(running.processIdentifier)), Keep Awake idle")
            return 0
        }
        if status.active, let session = status.session {
            let remaining = session.formattedRemaining(at: Date())
            let mode = status.closedLidProtected ? "closed-lid protected" : "lid-open only"
            print("Keep Awake: active (\(remaining) left, \(mode))")
            if session.keepDisplayAwake { print("Display: staying on & unlocked") }
            if status.lowPowerByUs { print("Low Power Mode: active (managed)") }
        } else {
            print("Keep Awake: idle (closed-lid sudoers: \(status.sudoersReady ? "ready" : "not configured"))")
        }
        if let err = status.lastError {
            print("Warning: \(err)")
        }
        return 0
    }

    private static func sendCommand(action: String, seconds: TimeInterval?) -> Int32 {
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
            forName: AwakeIPC.replyNotification(for: bundleID),
            object: nil,
            queue: nil
        ) { notification in
            guard let id = notification.userInfo?[AwakeIPC.requestIDKey] as? String, id == requestID else { return }
            box.ok = (notification.userInfo?[AwakeIPC.okKey] as? Bool) ?? true
            box.message = (notification.userInfo?[AwakeIPC.messageKey] as? String) ?? ""
            box.received = true
        }
        defer { center.removeObserver(observer) }

        var info: [String: Any] = [
            AwakeIPC.actionKey: action,
            AwakeIPC.requestIDKey: requestID,
        ]
        if let seconds { info[AwakeIPC.secondsKey] = seconds }

        center.postNotificationName(
            AwakeIPC.commandNotification(for: bundleID),
            object: nil,
            userInfo: info,
            deliverImmediately: true
        )

        let deadline = Date().addingTimeInterval(5.0)
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

        print("Sent '\(action)' to Screen Journal.")
        return 0
    }

    /// Crash-recovery entry point invoked every minute by launchd while an awake session is armed.
    private static func runBackstop() -> Int32 {
        do {
            try AwakeStore.withLock(timeout: 5.0) {
                let session = AwakeStore.readSession()
                var journal = AwakeStore.readJournal()

                // Leave a healthy, unexpired session alone while the app is alive.
                if let session, !session.isExpired(at: Date()), runningApp() != nil {
                    return
                }

                // Restore any pmset changes Screen Journal owns.
                if journal.sleepDisabledByUs {
                    try PmsetBridge.setSleepDisabled(false)
                    journal.sleepDisabledByUs = false
                }
                if journal.lowPowerSetByUs {
                    try PmsetBridge.setLowPowerMode(false)
                    journal.lowPowerSetByUs = false
                }
                try AwakeStore.writeJournal(journal)
                AwakeStore.removeSession()
                AwakeBackstopAgent.disarm()
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Backstop recovery deferred: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
