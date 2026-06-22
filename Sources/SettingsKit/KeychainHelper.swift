import Foundation

/// Minimal keychain-backed save counter. The settings screen only needs the
/// clear step (used by the debug-only "Clear Data" row), but the full counter is
/// kept here so the host app can share a single implementation if it wants.
final class KeychainHelper {

    private let service: String
    private let saveCountKey = "saveCount"

    init(service: String) {
        self.service = service
    }

    func getSaveCount() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: saveCountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let count = String(data: data, encoding: .utf8),
              let intValue = Int(count) else {
            return 0
        }
        return intValue
    }

    /// Clear save count (delete the keychain item).
    func clearSaveCount() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: saveCountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
