import AppKit
import JournalCore

/// Watches keys and clicks in every app for taps of one modifier key alone (the dictation key, Left ⌘ for WhatsApp), and for Esc.
/// Sees other apps' events only with the Accessibility grant, and only if it had the grant when it started.
@MainActor
final class KeyWatcher {
    private static let escape: UInt16 = 53
    private static let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]

    /// Left ⌘, as `NSEvent` reports it.
    static let leftCommand = (keyCode: UInt16(55), deviceMask: UInt(0x08))

    private let keyCode: UInt16?
    private let deviceMask: UInt
    private let onTap: () -> Void
    private let onDoubleTap: (() -> Void)?
    private let onEscape: () -> Void
    private var tap = ModifierTap()
    private var gesture = ModifierGesture()
    private var pendingTap: Task<Void, Never>?
    private var monitors: [Any] = []

    convenience init(key: DictationKey, onTap: @escaping () -> Void, onDoubleTap: @escaping () -> Void, onEscape: @escaping () -> Void) {
        self.init(keyCode: key.keyCode, deviceMask: key.deviceMask, onDoubleTap: onDoubleTap, onTap: onTap, onEscape: onEscape)
    }

    init(keyCode: UInt16?, deviceMask: UInt, onDoubleTap: (() -> Void)? = nil, onTap: @escaping () -> Void, onEscape: @escaping () -> Void = {}) {
        self.keyCode = keyCode
        self.deviceMask = deviceMask
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
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
        pendingTap?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == Self.escape { onEscape() }
        let kind = kind(of: event)
        guard let onDoubleTap else {
            if tap.feed(kind, at: event.timestamp) { onTap() }
            return
        }
        switch gesture.feed(kind, at: event.timestamp) {
        case .wait:
            pendingTap?.cancel()
            pendingTap = Task { [weak self] in
                try? await Task.sleep(for: .seconds(ModifierGesture.interval))
                guard !Task.isCancelled, let self else { return }
                if self.gesture.flush() == .single { self.onTap() }
            }
        case .double:
            pendingTap?.cancel()
            onDoubleTap()
        case .none, .single: break
        }
    }

    private func kind(of event: NSEvent) -> ModifierTap.Event {
        guard event.type == .flagsChanged, event.keyCode == keyCode else { return .other }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let ownModifier: NSEvent.ModifierFlags = keyCode == DictationKey.rightOption.keyCode ? .option : .command
        guard modifiers.subtracting(ownModifier).isEmpty else { return .other }
        return event.modifierFlags.rawValue & deviceMask != 0 ? .down : .up
    }
}
