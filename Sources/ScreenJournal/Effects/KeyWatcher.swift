import AppKit
import JournalCore

/// Watches keys and clicks in every app for taps of the dictation key, and for Esc.
/// Sees other apps' events only with the Accessibility grant, and only if it had the grant when it started.
@MainActor
final class KeyWatcher {
    private static let escape: UInt16 = 53
    private static let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]

    private let key: DictationKey
    private let onTap: () -> Void
    private let onEscape: () -> Void
    private var tap = ModifierTap()
    private var monitors: [Any] = []

    init(key: DictationKey, onTap: @escaping () -> Void, onEscape: @escaping () -> Void) {
        self.key = key
        self.onTap = onTap
        self.onEscape = onEscape
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    isolated deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == Self.escape { onEscape() }
        if tap.feed(kind(of: event), at: event.timestamp) { onTap() }
    }

    private func kind(of event: NSEvent) -> ModifierTap.Event {
        guard event.type == .flagsChanged, event.keyCode == key.keyCode else { return .other }
        return event.modifierFlags.rawValue & key.deviceMask != 0 ? .down : .up
    }
}
