import Foundation
import JournalCore
import Security

/// The AI Gateway key, in the login Keychain. Saved from Settings; read by `label`, which is the same signed binary,
/// so the command line reads it without a prompt and the key never passes through a file, the journal or a terminal.
enum GatewayKey {
    static let envName = "AI_GATEWAY_API_KEY"
    private static let service = "Screen Journal"
    private static let account = envName

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    /// The environment wins, so a developer's key overrides the saved one.
    static func current() -> String? {
        ProcessInfo.processInfo.environment[envName].flatMap { $0.isEmpty ? nil : $0 } ?? read()
    }

    /// Read once per launch and then kept in memory: a self-signed app is trusted per build, so every read
    /// by a new build (a rebuild, an update) shows a Keychain prompt until "Always Allow".
    /// A refusal is kept too, so it isn't asked again on every dictation.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var remembered: String??

    static func read() -> String? {
        lock.withLock {
            if let remembered { return remembered }
            let key = readKeychain()
            remembered = .some(key)
            return key
        }
    }

    private static func readKeychain() -> String? {
        var result: AnyObject?
        var lookup = query
        lookup[kSecReturnData as String] = true
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        let key = String(decoding: data, as: UTF8.self)
        return key.isEmpty ? nil : key
    }

    static var isSaved: Bool { read() != nil }

    static func save(_ key: String) -> Result<Void, LabelError> {
        remove()
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess { lock.withLock { remembered = .some(key) } }
        return status == errSecSuccess ? .success(()) : .failure(LabelError(message: "Keychain refused the key (\(status))."))
    }

    static func remove() {
        SecItemDelete(query as CFDictionary)
        lock.withLock { remembered = .some(nil) }
    }
}
