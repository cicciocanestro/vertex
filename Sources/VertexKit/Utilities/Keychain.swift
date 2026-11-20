import Foundation
import Security

/// Minimal generic-password storage for the SOCKS5 credential. The app is not
/// sandboxed, so the login keychain is available; the password no longer lives
/// in the UserDefaults plist.
enum Keychain {
    private static let service = "app.vertex.torrent"
    private static let account = "socks5-password"

    /// The custom test runner is a different ad-hoc binary: reading the app's
    /// keychain item would trigger an access prompt. Tests disable the
    /// keychain explicitly (Scripts/run-tests.sh) and via the process name.
    private static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["VERTEX_KEYCHAIN_DISABLED"] == "1" {
            return false
        }
        return ProcessInfo.processInfo.processName != "VertexTestRunner"
    }

    /// Stores (or deletes, when empty) the proxy password. Returns false when
    /// the keychain rejects the operation, so the caller can warn the user.
    @discardableResult
    static func setProxyPassword(_ password: String) -> Bool {
        guard isEnabled else { return false }
        if password.isEmpty {
            deleteProxyPassword()
            return true
        }

        let data = Data(password.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    enum ReadError: Error, Equatable {
        case disabled
        case unexpectedStatus(OSStatus)
    }

    /// Reads the password, keeping "there is no item" (`success(nil)`) distinct
    /// from "the read failed": the caller must retry the latter instead of
    /// caching an empty password for the rest of the process.
    static func readProxyPassword() -> Result<String?, ReadError> {
        guard isEnabled else { return .failure(.disabled) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return .success(nil)
        }
        guard status == errSecSuccess else {
            return .failure(.unexpectedStatus(status))
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return .success(nil)
        }
        return .success(value)
    }

    static func proxyPassword() -> String? {
        if case .success(let value) = readProxyPassword() {
            return value
        }
        return nil
    }

    static func deleteProxyPassword() {
        guard isEnabled else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
