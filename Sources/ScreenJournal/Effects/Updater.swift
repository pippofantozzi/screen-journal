import Sparkle

/// Sparkle, only when the bundle is configured with a feed (release builds).
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = configured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
