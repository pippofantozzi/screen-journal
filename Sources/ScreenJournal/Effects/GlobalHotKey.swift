import Carbon.HIToolbox

/// One system-wide shortcut through Carbon's RegisterEventHotKey: fires from any app and needs no Accessibility access.
/// Unregistered when released.
@MainActor
final class GlobalHotKey {
    /// ⌥Space: one easy chord, free in macOS; ChatGPT's desktop app claims it by default.
    static let note = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Space")

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// `nil` when another app already holds the combination.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &pressed, context, &handler) == noErr,
              RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x534A_4E54), id: 1),
                                  GetApplicationEventTarget(), 0, &hotKey) == noErr
        else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
