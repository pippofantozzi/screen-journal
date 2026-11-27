import JournalCore
import PaneCore
import SwiftUI

/// Enable/disable toggle, Accessibility status, active display profile, and compact shortcut cheat-sheet for window management.
struct WindowsSettings: View {
    let windowManager: WindowManagerController
    @AppStorage(Preferences.windowManagerEnabled) private var enabled = true
    @Environment(\.language) private var language
    @State private var trusted = WindowContext.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle(language("Window shortcuts (⌃⌥)"), isOn: $enabled)

                if !trusted {
                    LabeledContent(language("Accessibility")) {
                        Button(language("Allow…"), action: WindowContext.requestTrust)
                    }
                }

                LabeledContent(language("Display profile")) {
                    Text(profileSummary)
                        .foregroundStyle(.secondary)
                }

                if enabled {
                    LabeledContent(language("Right browser")) {
                        Text(windowManager.activeRightBrowser.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(language("Uses ⌃⌥ shortcuts that never clash with dictation, Spotlight, or accents."))
            }

            if enabled {
                Section {
                    ForEach(HotKeyLegendItem.scenes) { item in
                        LabeledContent {
                            cap(item.shortcut)
                        } label: {
                            Text(language(item.title))
                            Text(language(item.detail))
                        }
                    }
                } header: {
                    Text(language("Scenes"))
                }

                Section {
                    ForEach(HotKeyLegendItem.snaps) { item in
                        LabeledContent {
                            cap(item.shortcut)
                        } label: {
                            Text(language(item.title))
                            Text(language(item.detail))
                        }
                    }
                } header: {
                    Text(language("Snaps & Undo"))
                }

                Section {
                    ForEach(HotKeyLegendItem.summon) { item in
                        LabeledContent(item.title) {
                            cap(item.shortcut)
                        }
                    }
                } header: {
                    Text(language("Summon or Cycle"))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { windowManager.setEnabled(enabled) }
        .task {
            while !Task.isCancelled {
                trusted = WindowContext.isTrusted
                windowManager.refreshStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var profileSummary: String {
        switch windowManager.profile.kind {
        case .laptopOnly:
            return language("Laptop · %@", windowManager.profile.primaryWorkDisplay.resolutionLabel)
        case .dualDisplay:
            return language(
                "Dual Display · %@ + %@",
                windowManager.profile.primaryWorkDisplay.resolutionLabel,
                windowManager.profile.companionDisplay.resolutionLabel
            )
        }
    }

    private func cap(_ name: String) -> some View {
        Text(name)
            .font(.callout.monospaced().weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.5)))
    }
}
