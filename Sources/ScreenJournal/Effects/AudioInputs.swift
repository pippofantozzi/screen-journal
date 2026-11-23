import CoreAudio

/// Audio inputs found through Core Audio. Automatic mode uses the system's default input when it is wired
/// or built-in (so USB mics, Studio Display mics and clamshell mode work), and avoids Bluetooth headsets
/// (which spend seconds switching into call mode and drop music quality) unless explicitly selected in Settings.
enum AudioInputs {
    struct Input: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let isBuiltIn: Bool
        let isBluetooth: Bool
    }

    /// All connected audio inputs, wired and built-in first, Bluetooth after.
    static func available() -> [Input] {
        devices().compactMap { device -> Input? in
            guard hasInput(device), let uid = string(device, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = string(device, kAudioObjectPropertyName) ?? uid
            let kind = transport(device)
            return Input(
                id: uid,
                name: name,
                isBuiltIn: kind == kAudioDeviceTransportTypeBuiltIn,
                isBluetooth: isBluetoothTransport(kind)
            )
        }
        .sorted { ($0.isBluetooth ? 1 : 0, $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending ? 0 : 1) < ($1.isBluetooth ? 1 : 0, 1) }
    }

    /// The Core Audio UID to record from: the user's explicit choice if connected, otherwise the default input
    /// when it isn't Bluetooth, falling back to the built-in or first non-Bluetooth mic.
    static func preferred(savedUID: String?) -> String? {
        let inputs = available()
        if let savedUID, !savedUID.isEmpty, inputs.contains(where: { $0.id == savedUID }) {
            return savedUID
        }
        if let defaultID = defaultInputDevice(), hasInput(defaultID), !isBluetoothTransport(transport(defaultID)),
           let uid = string(defaultID, kAudioDevicePropertyDeviceUID) {
            return uid
        }
        return builtIn() ?? inputs.first(where: { !$0.isBluetooth })?.id
    }

    /// Its id, as `Microphone` opens it; nil on a Mac without one, which then records from the system's default input.
    static func builtIn() -> String? {
        devices().first { hasInput($0) && transport($0) == kAudioDeviceTransportTypeBuiltIn }
            .flatMap { string($0, kAudioDevicePropertyDeviceUID) }
    }

    private static func isBluetoothTransport(_ kind: UInt32) -> Bool {
        kind == kAudioDeviceTransportTypeBluetooth || kind == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var value = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr,
              value != kAudioObjectUnknown
        else { return nil }
        return value
    }

    private static func devices() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var streams = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr && size > 0
    }

    private static func transport(_ device: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
