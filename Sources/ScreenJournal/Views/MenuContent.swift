import JournalCore
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
        // Shows ⌥Space beside the item, so the menu teaches the shortcut that works everywhere.
        Button(language("Note This Moment…")) { windows.showNote() }
            .keyboardShortcut(.space, modifiers: .option)
        Button(language("Your Week…")) { windows.showWeek() }
        // One place for everything else, so there's never a second place to look.
        Button(language("Settings…")) { windows.showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button(language("Quit Screen Journal")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
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
