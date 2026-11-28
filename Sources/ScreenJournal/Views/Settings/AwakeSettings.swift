import JournalCore
import SwiftUI

/// Controls closed-lid sleep prevention, optional display-awake hold, battery/thermal floors, and sudoers setup.
struct AwakeSettings: View {
    let awake: AwakeController
    @AppStorage(Preferences.awakeKeepDisplay) private var keepDisplay = false
    @AppStorage(Preferences.awakeLowPowerOnLidClose) private var lowPowerOnLidClose = true
    @AppStorage(Preferences.awakeLowPowerFloor) private var lowPowerFloor = 40
    @AppStorage(Preferences.awakeEndFloor) private var endFloor = 10
    @AppStorage(Preferences.awakeThermalRules) private var thermalRules = true
    @Environment(\.language) private var language
    @State private var copiedCommand = false

    var body: some View {
        Form {
            Section {
                LabeledContent(language("Status")) {
                    if let session = awake.session {
                        let until = session.endsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.locale))
                        HStack(spacing: 8) {
                            Text(language("%@ left (until %@)", awake.countdownText, until))
                                .foregroundStyle(.secondary)
                            Button(language("Stop")) {
                                Task { _ = await awake.endSession(reason: .user) }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(language("Idle"))
                                .foregroundStyle(.secondary)
                            Button(language("Start 4 Hours")) {
                                Task { _ = await awake.startSession(duration: AwakeSession.defaultDuration) }
                            }
                        }
                    }
                }

                if awake.isActive {
                    LabeledContent(language("Closed-lid access")) {
                        Text(awake.closedLidProtected ? language("Closed-lid protected") : language("Lid-open only"))
                            .foregroundStyle(awake.closedLidProtected ? .green : .orange)
                    }
                }
            }

            Section {
                Toggle(language("Keep screen on and unlocked"), isOn: $keepDisplay)
                Toggle(language("Low Power Mode when lid closes"), isOn: $lowPowerOnLidClose)
            } header: {
                Text(language("Display & Lid"))
            } footer: {
                Text(language("Holds the display awake so screen-driving agents don't hit the lock screen. macOS restores normal idle sleep when the session ends."))
            }

            Section {
                Stepper(
                    lowPowerFloor > 0
                        ? language("Low Power Mode below %@%%", "\(lowPowerFloor)")
                        : language("Low Power Mode on battery: Off"),
                    value: $lowPowerFloor,
                    in: 0...80,
                    step: 5
                )
                Stepper(
                    endFloor > 0
                        ? language("End session below %@%%", "\(endFloor)")
                        : language("Battery end floor: Off"),
                    value: $endFloor,
                    in: 0...50,
                    step: 5
                )
                Toggle(language("Thermal protection"), isOn: $thermalRules)
            } header: {
                Text(language("Battery & Heat"))
            } footer: {
                Text(language("Turns on Low Power Mode when hot or on low battery, and ends the session before the battery runs dry or the Mac overheats."))
            }

            Section {
                LabeledContent(language("Passwordless pmset")) {
                    HStack(spacing: 8) {
                        Text(awake.sudoersReady ? language("Ready") : language("Not configured"))
                            .foregroundStyle(awake.sudoersReady ? .green : .orange)
                        if !awake.sudoersReady {
                            Button(action: copySetupCommand) {
                                Label(
                                    copiedCommand ? language("Copied") : language("Copy Setup Command"),
                                    systemImage: copiedCommand ? "checkmark" : "doc.on.doc"
                                )
                                .contentTransition(.symbolEffect(.replace))
                            }
                            Button(language("Recheck"), action: awake.recheckSudoers)
                        }
                    }
                }
            } header: {
                Text(language("Closed-lid access"))
            } footer: {
                Text(language("Lets Screen Journal disable lid-close sleep safely via pmset and restore it automatically when the timer ends or the app quits."))
            }
        }
        .formStyle(.grouped)
        .onChange(of: keepDisplay) { awake.applySettingsChange() }
        .onChange(of: lowPowerOnLidClose) { awake.applySettingsChange() }
        .onChange(of: lowPowerFloor) { awake.applySettingsChange() }
        .onChange(of: endFloor) { awake.applySettingsChange() }
        .onChange(of: thermalRules) { awake.applySettingsChange() }
        .onAppear { awake.recheckSudoers() }
    }

    private func copySetupCommand() {
        Clipboard.write(PmsetBridge.sudoersSetupCommand())
        withAnimation(.spring(duration: 0.3)) { copiedCommand = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.spring(duration: 0.3)) { copiedCommand = false }
        }
    }
}
