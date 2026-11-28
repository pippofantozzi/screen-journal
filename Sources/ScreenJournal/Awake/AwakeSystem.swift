import CoreGraphics
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import JournalCore

struct PmsetError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

/// Thin adapter over `pmset` and passwordless `sudo -n /usr/bin/pmset` commands.
enum PmsetBridge {
    private static let sudoPath = "/usr/bin/sudo"
    private static let pmsetPath = "/usr/bin/pmset"

    struct CommandOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { status == 0 }
    }

    /// Runs a short-lived system command synchronously with a bounded timeout.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        final class DataBox: @unchecked Sendable {
            var data = Data()
        }
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return CommandOutput(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(25_000)
        }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < grace {
                usleep(25_000)
            }
            return CommandOutput(status: -1, stdout: "", stderr: "Command timed out: \(executable)")
        }

        group.wait()
        let stdout = String(data: outBox.data, encoding: .utf8) ?? ""
        let stderr = String(data: errBox.data, encoding: .utf8) ?? ""
        return CommandOutput(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    /// Non-destructive check for whether passwordless sudoers allows `pmset -a disablesleep 1`.
    static func isPasswordlessSudoAvailable() -> Bool {
        run(sudoPath, ["-n", "-l", pmsetPath, "-a", "disablesleep", "1"], timeout: 5).succeeded
    }

    static func setSleepDisabled(_ disabled: Bool) throws {
        let value = disabled ? "1" : "0"
        let out = run(sudoPath, ["-n", pmsetPath, "-a", "disablesleep", value])
        guard out.succeeded else {
            let detail = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PmsetError(message: detail.isEmpty ? "pmset disablesleep \(value) failed (exit \(out.status))." : detail)
        }
    }

    static func isSleepDisabled() throws -> Bool {
        let out = run(pmsetPath, ["-g"])
        guard out.succeeded, let disabled = PmsetParser.readSleepDisabled(out.stdout) else {
            throw PmsetError(message: "Couldn't read SleepDisabled from pmset -g.")
        }
        return disabled
    }

    static func setLowPowerMode(_ on: Bool) throws {
        let value = on ? "1" : "0"
        let out = run(sudoPath, ["-n", pmsetPath, "-b", "lowpowermode", value])
        guard out.succeeded else {
            let detail = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PmsetError(message: detail.isEmpty ? "pmset lowpowermode \(value) failed (exit \(out.status))." : detail)
        }
    }

    static func isLowPowerModeOn() throws -> Bool? {
        let out = run(pmsetPath, ["-g", "custom"])
        guard out.succeeded else {
            throw PmsetError(message: "Couldn't read pmset -g custom.")
        }
        return PmsetParser.parseLowPowerMode(out.stdout)
    }

    /// Safe one-line Terminal command to install a least-privilege sudoers rule for closed-lid awake.
    static func sudoersSetupCommand(user: String = NSUserName()) -> String {
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -b lowpowermode 0"
        return "printf '%s\\n' '\(rule)' | sudo tee /etc/sudoers.d/screen-journal >/dev/null && sudo chmod 0440 /etc/sudoers.d/screen-journal && sudo visudo -cf /etc/sudoers.d/screen-journal"
    }
}

/// Process-scoped IOKit power assertions: always prevents idle system sleep while active,
/// and optionally prevents idle display sleep (keeps screen on & unlocked for GUI agents).
/// Automatically released by macOS if the process exits or crashes, and bounded by a kernel timeout.
final class IOPMAssertionGuard {
    private var systemAssertionID: IOPMAssertionID?
    private var displayAssertionID: IOPMAssertionID?

    func acquire(keepDisplayAwake: Bool, timeout: TimeInterval) {
        releaseAll()
        systemAssertionID = createAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep,
            name: "Screen Journal Keep Awake (system)",
            timeout: timeout
        )
        if keepDisplayAwake {
            displayAssertionID = createAssertion(
                type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                name: "Screen Journal Keep Awake (display)",
                timeout: timeout
            )
        }
    }

    func setDisplayAwake(_ on: Bool, timeout: TimeInterval) {
        if on {
            if let id = displayAssertionID {
                _ = renewAssertion(id, timeout: timeout)
            } else {
                displayAssertionID = createAssertion(
                    type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                    name: "Screen Journal Keep Awake (display)",
                    timeout: timeout
                )
            }
        } else if let id = displayAssertionID {
            IOPMAssertionRelease(id)
            displayAssertionID = nil
        }
    }

    func renew(timeout: TimeInterval) {
        if let id = systemAssertionID {
            _ = renewAssertion(id, timeout: timeout)
        }
        if let id = displayAssertionID {
            _ = renewAssertion(id, timeout: timeout)
        }
    }

    func releaseAll() {
        if let id = systemAssertionID {
            IOPMAssertionRelease(id)
            systemAssertionID = nil
        }
        if let id = displayAssertionID {
            IOPMAssertionRelease(id)
            displayAssertionID = nil
        }
    }

    deinit {
        releaseAll()
    }

    private func createAssertion(type: String, name: String, timeout: TimeInterval) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let seconds = max(60, Int(ceil(timeout)))
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionLevelKey: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            kIOPMAssertionNameKey: name,
            kIOPMAssertionTimeoutKey: seconds,
            kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionTurnOff,
        ]
        let status = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        return status == kIOReturnSuccess ? id : nil
    }

    private func renewAssertion(_ id: IOPMAssertionID, timeout: TimeInterval) -> Bool {
        let seconds = max(60, Int(ceil(timeout)))
        return IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey as CFString, seconds as CFNumber) == kIOReturnSuccess
    }
}

/// Requests system sleep once `disablesleep` is restored and the laptop lid is closed.
enum ClosedLidSleeper {
    static func requestSleep() {
        let connect = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connect != 0 else { return }
        defer { IOServiceClose(connect) }
        _ = IOPMSleepSystem(connect)
    }
}

/// Reads live battery, charging, thermal, and lid state from IOKit / ProcessInfo.
enum HardwareMonitor {
    struct Snapshot: Sendable {
        let batteryPercent: Int?
        let isCharging: Bool
        let thermal: AwakeThermalState
        let lidClosed: Bool
    }

    static func readSnapshot() -> Snapshot {
        let battery = readBattery()
        return Snapshot(
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            thermal: readThermalState(),
            lidClosed: isLidClosedWithoutExternalDisplay()
        )
    }

    static func readBattery() -> (percent: Int?, isCharging: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, true) }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int
            let percent: Int?
            if let current, let maxCap, maxCap > 0 {
                percent = Int(round(Double(current) / Double(maxCap) * 100.0))
            } else {
                percent = current
            }
            let powerSource = desc[kIOPSPowerSourceStateKey] as? String
            let isCharging = powerSource == kIOPSACPowerValue || (desc[kIOPSPowerSourceStateKey] as? String != kIOPSBatteryPowerValue)
            return (percent, isCharging)
        }
        // Desktop Mac (no internal battery): treat as always powered.
        return (nil, true)
    }

    static func readThermalState() -> AwakeThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    /// True only when the built-in lid is shut AND no real external display is attached (so clamshell-at-desk stays open).
    static func isLidClosedWithoutExternalDisplay() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let closed = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool,
              closed
        else { return false }

        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return true }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return true }

        // Virtual/placeholder displays macOS creates when lid is closed use vendor 0x756e6b6e ("unkn").
        let unknownVendor: UInt32 = 0x756e_6b6e
        let hasExternal = displays.prefix(Int(count)).contains { id in
            CGDisplayIsBuiltin(id) == 0 && CGDisplayVendorNumber(id) != unknownVendor
        }
        return !hasExternal
    }
}

/// Manages a lightweight per-user launchd backstop that runs `ScreenJournal awake backstop` every minute
/// while an awake session holds `disablesleep`, restoring sleep if the app crashes past the deadline.
enum AwakeBackstopAgent {
    static let label = "com.filippofantozzi.ScreenJournal.awake-backstop"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(label).plist")
    }

    static func arm() {
        // Only install from a bundled .app so `swift test` or temporary dev binaries don't leave broken agents.
        guard Bundle.main.bundleURL.pathExtension == "app",
              let executable = Bundle.main.executablePath
        else { return }

        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "awake", "backstop"],
            "StartInterval": 60,
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        do {
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return
        }

        let domain = "gui/\(getuid())"
        _ = PmsetBridge.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 5)
        _ = PmsetBridge.run("/bin/launchctl", ["bootstrap", domain, plistURL.path], timeout: 5)
    }

    static func disarm() {
        let domain = "gui/\(getuid())"
        _ = PmsetBridge.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 5)
        try? FileManager.default.removeItem(at: plistURL)
    }
}
