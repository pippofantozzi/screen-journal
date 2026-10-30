import Carbon.HIToolbox

/// One system-wide shortcut through Carbon's RegisterEventHotKey: fires from any app and needs no Accessibility access.
/// Each has its own id, so several can be registered at once. Unregistered when released.
@MainActor
final class GlobalHotKey {
    /// ⌥Space: one easy chord, free in macOS; ChatGPT's desktop app claims it by default.
    static let note = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥Space")
    private static var lastID: UInt32 = 0

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32

    /// `nil` when another app already holds the combination.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        Self.lastID += 1
        id = Self.lastID
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Every registered shortcut's handler hears every press; each passes on the ones that aren't its own.
        let callback: EventHandlerUPP = { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            guard pressedID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &pressed, context, &handler) == noErr,
              RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x534A_4E54), id: id),
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
