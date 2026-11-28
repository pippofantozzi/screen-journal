import JournalCore
import SwiftUI

struct StatusIcon: View {
    let model: AppModel
    let awake: AwakeController

    var body: some View {
        if awake.isActive, !awake.countdownText.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(awake.countdownText)
                    .monospacedDigit()
            }
        } else {
            Image(systemName: symbol)
        }
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

    private var awake: AwakeController { windows.awake }

    var body: some View {
        Text(headline)

        if let awakeLine {
            Text(awakeLine)
        }

        if let error = awake.lastError {
            Text(error)
        }

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

        awakeMenu

        Divider()

        Button(language("Settings…")) { windows.showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button(language("Quit Screen Journal")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var awakeMenu: some View {
        if awake.isActive {
            Menu(language("Keep Awake · %@", awake.countdownText)) {
                Button(language("Extend +30 Minutes")) {
                    Task { _ = await awake.extendSession(by: 30 * 60) }
                }
                Button(language("Extend +1 Hour")) {
                    Task { _ = await awake.extendSession(by: 60 * 60) }
                }
                Button(language("Extend +2 Hours")) {
                    Task { _ = await awake.extendSession(by: 2 * 60 * 60) }
                }
                Divider()
                Button(language("Stop Keeping Awake")) {
                    Task { _ = await awake.endSession(reason: .user) }
                }
            }
        } else {
            Menu(language("Keep Awake")) {
                Button(language("30 Minutes")) {
                    Task { _ = await awake.startSession(duration: 30 * 60) }
                }
                Button(language("1 Hour")) {
                    Task { _ = await awake.startSession(duration: 60 * 60) }
                }
                Button(language("2 Hours")) {
                    Task { _ = await awake.startSession(duration: 2 * 60 * 60) }
                }
                Button(language("4 Hours")) {
                    Task { _ = await awake.startSession(duration: 4 * 60 * 60) }
                }
                Button(language("8 Hours")) {
                    Task { _ = await awake.startSession(duration: 8 * 60 * 60) }
                }
            }
        }
    }

    private var awakeLine: String? {
        guard let session = awake.session else { return nil }
        let until = session.endsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.locale))
        return language("Awake · %@ left (until %@)", awake.countdownText, until)
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
