import Carbon.HIToolbox
import Foundation

/// Registers system-wide Carbon hotkeys (`RegisterEventHotKey`) through a single application event handler.
/// Uses signature `"SJWM"` so it coexists cleanly alongside `GlobalHotKey` (`"SJNT"`, `⌥Space`).
@MainActor
final class HotKeyCenter {
    struct Binding {
        let label: String
        let keyCode: UInt32
        let modifiers: UInt32
        let action: @MainActor () -> Void
    }

    private static let signature: OSType = 0x534A_574D // "SJWM"

    private var handler: EventHandlerRef?
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 0

    private(set) var registeredCount: Int = 0
    private(set) var failedLabels: [String] = []

    init() {
        installHandler()
    }

    func registerAll(_ bindings: [Binding]) {
        unregisterAll()
        failedLabels = []
        registeredCount = 0

        for binding in bindings {
            nextID += 1
            let id = nextID
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeys[id] = ref
                actions[id] = binding.action
                registeredCount += 1
            } else {
                failedLabels.append(binding.label)
            }
        }
    }

    func unregisterAll() {
        for ref in hotKeys.values {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
        actions.removeAll()
        registeredCount = 0
    }

    func tearDown() {
        unregisterAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard err == noErr, pressedID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            let handled = MainActor.assumeIsolated {
                guard let action = center.actions[pressedID.id] else { return false }
                action()
                return true
            }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, context, &handler)
    }
}
