import Foundation
import JournalCore
import Security

/// The AI Gateway key, in the login Keychain. Saved from Settings; read by `label`, which is the same signed binary,
/// so the command line reads it without a prompt and the key never passes through a file, the journal or a terminal.
enum GatewayKey {
    private static let service = "Screen Journal"
    private static let account = DecisionGateway.keyName

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
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
        return status == errSecSuccess ? .success(()) : .failure(LabelError(message: "Keychain refused the key (\(status))."))
    }

    static func remove() {
        SecItemDelete(query as CFDictionary)
    }
}
