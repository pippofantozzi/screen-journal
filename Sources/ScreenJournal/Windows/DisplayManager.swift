import AppKit
import CoreGraphics
import PaneCore

/// Tracks connected displays in AX (top-left origin) coordinates and resolves Laptop vs Dual-Display profiles.
@MainActor
final class DisplayManager {
    private var observer: NSObjectProtocol?
    private let onChange: @MainActor (DisplayProfile) -> Void

    private(set) var profile: DisplayProfile

    init(onChange: @escaping @MainActor (DisplayProfile) -> Void) {
        self.onChange = onChange
        self.profile = Self.currentProfile()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let next = Self.currentProfile()
        if next != profile {
            profile = next
            onChange(next)
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    static func currentProfile() -> DisplayProfile {
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            return DisplayProfile.resolve(displays: [])
        }
        let primaryHeight = primary.frame.height
        let descriptors: [DisplayDescriptor] = screens.enumerated().map { idx, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = CGDirectDisplayID(number?.uint32Value ?? UInt32(idx + 1))
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let isPrimary = CGDisplayIsMain(displayID) != 0 || idx == 0

            let axFrame = DisplayGeometry.appKitToAX(rect: screen.frame, primaryScreenHeight: primaryHeight)
            let axVisible = DisplayGeometry.appKitToAX(rect: screen.visibleFrame, primaryScreenHeight: primaryHeight)

            return DisplayDescriptor(
                id: displayID,
                name: screen.localizedName,
                frame: axFrame,
                visibleFrame: axVisible,
                isBuiltIn: isBuiltIn,
                isPrimary: isPrimary
            )
        }
        return DisplayProfile.resolve(displays: descriptors)
    }
}
