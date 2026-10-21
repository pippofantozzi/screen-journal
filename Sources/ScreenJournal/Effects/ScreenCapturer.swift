import CoreGraphics
import ScreenCaptureKit

struct DisplayShot {
    let index: Int
    let bounds: CGRect
    let image: CGImage
}

/// Thin adapter over ScreenCaptureKit: one still per display, main display first, private apps blanked out.
enum ScreenCapturer {
    static func captureAll(excludingBundleIDs excluded: Set<String>) async throws -> [DisplayShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let hidden = content.applications.filter {
            excluded.contains($0.bundleIdentifier) || $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let main = CGMainDisplayID()
        let displays = content.displays.sorted {
            ($0.displayID == main ? 0 : 1, $0.frame.minX) < ($1.displayID == main ? 0 : 1, $1.frame.minX)
        }

        var shots: [DisplayShot] = []
        for (offset, display) in displays.enumerated() {
            let filter = SCContentFilter(display: display, excludingApplications: hidden, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let mode = CGDisplayCopyDisplayMode(display.displayID)
            config.width = mode?.pixelWidth ?? display.width
            config.height = mode?.pixelHeight ?? display.height
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            shots.append(DisplayShot(index: offset + 1, bounds: CGDisplayBounds(display.displayID), image: image))
        }
        return shots
    }
}
