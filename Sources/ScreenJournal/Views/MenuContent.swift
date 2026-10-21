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

    var body: some View {
        Text(headline)

        if model.status == .needsScreenAccess {
            Button("Turn Screen Access Back On…") { windows.showOnboarding(at: .screenAccess) }
        }

        Divider()

        if model.pausedUntil == nil {
            Menu("Pause") {
                Button("For 15 Minutes") { model.pause(for: 15 * 60) }
                Button("For 1 Hour") { model.pause(for: 60 * 60) }
                Button("Until I Resume") { model.pause(for: nil) }
            }
        } else {
            Button("Resume") { model.resume() }
        }
        Button("Note This Moment…") { windows.showNote() }
            .keyboardShortcut("n")

        Divider()

        Button("How Screen Journal Works…") { windows.showGuide() }
        Button("Open Journal Folder") { model.openFolder() }
        Button("Settings…") { windows.showSettings() }
            .keyboardShortcut(",")
        if model.updater.isAvailable {
            Button("Check for Updates…") { model.updater.checkForUpdates() }
        }

        Divider()

        Button("Quit Screen Journal") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var headline: String {
        switch model.status {
        case .starting: "Starting…"
        case .recording: recordingLine
        case .paused: pausedLine
        case .resting: "Resting while you're away"
        case .needsScreenAccess: "Needs Screen Recording access"
        case .failing: "Can't capture right now"
        }
    }

    private var recordingLine: String {
        let moments = model.momentsToday == 1 ? "1 moment" : "\(model.momentsToday) moments"
        guard model.bytesToday > 0 else { return "Recording · \(moments) today" }
        return "Recording · \(moments) today · \(ByteCountFormatter.string(fromByteCount: model.bytesToday, countStyle: .file))"
    }

    private var pausedLine: String {
        guard let until = model.pausedUntil, until < .distantFuture else { return "Paused" }
        return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
    }
}
