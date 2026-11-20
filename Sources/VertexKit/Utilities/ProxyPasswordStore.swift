import Foundation

/// Storage for the SOCKS5 password.
///
/// The Keychain is the default and the safest option. macOS binds the item to
/// the app's code signature, which changes on every ad-hoc build (and on every
/// rebuild signed with a different certificate), so the system can ask again
/// for access. Users who prefer no prompts can switch to a file in Application
/// Support, readable by their account only (0600). The file is not encrypted:
/// the setting says so, and the Keychain remains the default.
package enum ProxyPasswordStore {
    package enum Storage {
        case keychain
        case file
    }

    package enum ReadError: Error {
        case disabled
        case unavailable
    }

    package static var storage: Storage {
        UserDefaults.standard.bool(forKey: PrefKey.proxyPasswordInFile) ? .file : .keychain
    }

    package static var fileURL: URL {
        // Test hook: the runner must never touch the user's real support folder.
        if let override = ProcessInfo.processInfo.environment["VERTEX_PROXY_PASSWORD_FILE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Vertex/proxy-password")
    }

    package static func read() -> Result<String?, ReadError> {
        switch storage {
        case .file:
            return readFile()
        case .keychain:
            switch Keychain.readProxyPassword() {
            case .success(let value):
                return .success(value)
            case .failure(.disabled):
                return .failure(.disabled)
            case .failure(.unexpectedStatus):
                return .failure(.unavailable)
            }
        }
    }

    @discardableResult
    package static func write(_ value: String) -> Bool {
        switch storage {
        case .file:
            return writeFile(value)
        case .keychain:
            let saved = Keychain.setProxyPassword(value)
            if saved { removeFile() }
            return saved
        }
    }

    /// Moves the password to the newly selected backend and removes the copy in
    /// the old one. `value` is the password the in-memory cache already holds.
    package static func migratePassword(_ value: String, toFile: Bool) {
        if toFile {
            guard writeFile(value) else { return }
            Keychain.deleteProxyPassword()
        } else {
            guard value.isEmpty || Keychain.setProxyPassword(value) else { return }
            removeFile()
        }
    }

    package static func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func readFile() -> Result<String?, ReadError> {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .success(nil)
        }
        do {
            let data = try Data(contentsOf: url)
            return .success(String(data: data, encoding: .utf8) ?? "")
        } catch {
            return .failure(.unavailable)
        }
    }

    private static func writeFile(_ value: String) -> Bool {
        if value.isEmpty {
            removeFile()
            return true
        }
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(value.utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }
}
