import JournalCore
import PaneCore
import SwiftUI

struct StatusIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch model.status {
        case .recording, .starting: "camera.aperture"
        case .paused: "pause.circle"
        case .resting: "moon.zzz"
        case .needsScreenAccess, .failing: "exclamationmark.triangle"
        }
    }
}

struct MenuContent: View {
    let model: AppModel
    let windows: WindowPresenter
    @AppStorage(Preferences.windowManagerEnabled) private var windowManagerEnabled = true
    @Environment(\.language) private var language

    var body: some View {
        Text(headline)

        if model.status == .needsScreenAccess {
            Button(language("Turn Screen Access Back On…")) { windows.showOnboarding(at: .screenAccess) }
        }

        Divider()

        if model.pausedUntil == nil {
            Menu(language("Pause")) {
                Button(language("For 15 Minutes")) { model.pause(for: 15 * 60) }
                Button(language("For 1 Hour")) { model.pause(for: 60 * 60) }
                Button(language("Until I Resume")) { model.pause(for: nil) }
            }
        } else {
            Button(language("Resume")) { model.resume() }
        }
        Button(language("Forget Last 15 Minutes…")) { windows.confirmForgetRecent(minutes: 15) }
        // Shows ⌥Space beside the item, so the menu teaches the shortcut that works everywhere.
        Button(language("Note This Moment…")) { windows.showNote() }
            .keyboardShortcut(.space, modifiers: .option)
        // In WhatsApp, a tap of Left ⌘ opens it too; a menu can't show a lone modifier.
        Button(language("Export WhatsApp Chat…")) { windows.showWhatsAppExport() }
        Button(language("Your Week…")) { windows.showWeek() }

        if windowManagerEnabled {
            windowsMenu
        }

        if windows.dictation.hasUnsent {
            Divider()
            Button(windows.dictation.unsentCount > 1
                ? language("Retry Last Dictation (%@)", "\(windows.dictation.unsentCount)")
                : language("Retry Last Dictation")) {
                windows.dictation.retry()
            }
            Button(language("Discard Unsent Dictation")) { windows.dictation.discardLastUnsent() }
        }
        if !windows.dictation.recent.isEmpty {
            Menu(language("Recent Dictations")) {
                ForEach(Array(windows.dictation.recent.enumerated()), id: \.offset) { _, text in
                    Button(preview(text)) { windows.dictation.copyRecent(text) }
                }
            }
        }

        Divider()

        // One place for everything else, so there's never a second place to look.
        Button(language("Settings…")) { windows.showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button(language("Quit Screen Journal")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var windowsMenu: some View {
        let wm = windows.windowManager
        return Menu(language("Windows")) {
            Text(wm.profile.summary)
            if !wm.isTrusted {
                Button(language("Allow Accessibility…"), action: WindowContext.requestTrust)
            }
            Divider()
            Button(wm.isDropAndSendActive
                ? language("Restore from Drop & Send (⌃⌥W)")
                : language("Drop & Send (⌃⌥W)")) {
                Task { _ = await wm.perform(.send) }
            }
            Button(language("Dev Split (⌃⌥1)")) {
                Task { _ = await wm.perform(.dev) }
            }
            Button(language("Swap Right Browser (⌃⌥B)")) {
                Task { _ = await wm.perform(.swapBrowser) }
            }
            Button(language("Dual Browser Split (⌃⌥2)")) {
                Task { _ = await wm.perform(.dualBrowser) }
            }
            Button(wm.isGrokDrawerActive
                ? language("Hide Grok Bot Drawer (⌃⌥G)")
                : language("Grok Bot Drawer (⌃⌥G)")) {
                Task { _ = await wm.perform(.grok) }
            }
            Divider()
            Button(language("Left Half (⌃⌥←)")) {
                Task { _ = await wm.perform(.snapLeft) }
            }
            Button(language("Right Half (⌃⌥→)")) {
                Task { _ = await wm.perform(.snapRight) }
            }
            Button(language("Maximize (⌃⌥↩)")) {
                Task { _ = await wm.perform(.snapMax) }
            }
            Button(language("Left Third (⌃⌥[)")) {
                Task { _ = await wm.perform(.snapLeftThird) }
            }
            Button(language("Right Two-Thirds (⌃⌥])")) {
                Task { _ = await wm.perform(.snapRightTwoThirds) }
            }
            Divider()
            Button(language("Undo Layout (⌃⌥U)")) {
                Task { _ = await wm.perform(.undo) }
            }
            .disabled(wm.undoDepth == 0)
        }
    }

    private func preview(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return singleLine.count > 48 ? String(singleLine.prefix(48)) + "…" : singleLine
    }

    private var headline: String {
        switch model.status {
        case .starting: language("Starting…")
        case .recording: recordingLine
        case .paused: pausedLine
        case .resting: language("Resting while you're away")
        case .needsScreenAccess: language("Needs Screen Recording access")
        case .failing: language("Can't capture right now")
        }
    }

    private var recordingLine: String {
        let moments = model.momentsToday == 1 ? language("1 moment") : language("%@ moments", model.momentsToday.formatted(.number.locale(language.locale)))
        guard model.bytesToday > 0 else { return language("Recording · %@ today", moments) }
        return language("Recording · %@ today · %@", moments, ByteCountFormatter.string(fromByteCount: model.bytesToday, countStyle: .file))
    }

    private var pausedLine: String {
        guard let until = model.pausedUntil, until < .distantFuture else { return language("Paused") }
        return language("Paused until %@", until.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.locale)))
    }
}
