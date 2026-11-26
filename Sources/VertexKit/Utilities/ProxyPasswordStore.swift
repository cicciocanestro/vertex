import Darwin
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
        Preferences.userDefaults.bool(forKey: PrefKey.proxyPasswordInFile) ? .file : .keychain
    }

    package static var fileURL: URL {
        // Test hook: the runner must never touch the user's real support folder.
        if let override = ProcessInfo.processInfo.environment["VERTEX_PROXY_PASSWORD_FILE"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        return Preferences.appSupportDirectory.appendingPathComponent("proxy-password")
    }

    /// Serializes every backend access. The cache in `Preferences` is updated
    /// inside `ioQueue` so concurrent warm reads, saves and backend migrations
    /// never leave `cachedProxyPassword` out of sync with persisted storage.
    private static let ioQueue = DispatchQueue(label: "com.vertex.proxy-password")

    static func withIOQueue<T>(_ body: () -> T) -> T {
        ioQueue.sync(execute: body)
    }

    package static func read() -> Result<String?, ReadError> {
        ioQueue.sync { readUnlocked() }
    }

    @discardableResult
    package static func write(_ value: String) -> Bool {
        ioQueue.sync { writeUnlocked(value) }
    }

    static func readUnlocked() -> Result<String?, ReadError> {
        readUnlocked(from: storage)
    }

    static func readUnlocked(from target: Storage) -> Result<String?, ReadError> {
        switch target {
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

    static func writeUnlocked(_ value: String) -> Bool {
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
    /// the old one. If the in-memory cache is still cold, reads directly from
    /// the source backend first and aborts without deleting the source on error.
    @discardableResult
    package static func migratePassword(_ value: String, toFile: Bool) -> Bool {
        ioQueue.sync {
            let effectiveValue: String
            if Preferences.isProxyPasswordCacheLoaded {
                effectiveValue = value
            } else {
                let source: Storage = toFile ? .keychain : .file
                switch readUnlocked(from: source) {
                case .success(let resolved):
                    let legacy = Preferences.userDefaults.string(forKey: PrefKey.proxyPassword) ?? ""
                    effectiveValue = resolved ?? legacy
                case .failure:
                    return false
                }
            }

            if toFile {
                guard writeFile(effectiveValue) else { return false }
                _ = Keychain.deleteProxyPassword()
            } else {
                if effectiveValue.isEmpty {
                    guard Keychain.deleteProxyPassword() else { return false }
                } else {
                    guard Keychain.setProxyPassword(effectiveValue) else { return false }
                }
                removeFile()
            }

            Preferences.commitCachedProxyPasswordFromIOQueue(effectiveValue)
            return true
        }
    }

    private static func removeFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func readFile() -> Result<String?, ReadError> {
        let url = fileURL
        // O_NOFOLLOW is the read counterpart of the write path: a symlink is
        // not a password file. It is ignored (the next save replaces it) and
        // the file it points to is neither read nor chmod'ed.
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ELOOP {
                return .success(nil)
            }
            return .failure(.unavailable)
        }
        defer { close(descriptor) }

        var info = stat()
        guard
            fstat(descriptor, &info) == 0,
            (info.st_mode & S_IFMT) == S_IFREG
        else {
            return .failure(.unavailable)
        }
        // Tighten through the descriptor, so the mode change cannot be
        // redirected to a different path between check and chmod.
        if info.st_mode & 0o077 != 0 {
            _ = fchmod(descriptor, 0o600)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let limit = 64 * 1024
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return .failure(.unavailable)
            }
            data.append(contentsOf: buffer[0..<count])
            if data.count > limit {
                return .failure(.unavailable)
            }
        }
        return .success(String(data: data, encoding: .utf8) ?? "")
    }

    private static func writeFile(_ value: String) -> Bool {
        if value.isEmpty {
            removeFile()
            return true
        }
        let url = fileURL
        let folder = url.deletingLastPathComponent()
        let temporary =
            folder
            .appendingPathComponent(".proxy-password-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // `createDirectory` ignores attributes when the folder already
            // exists: older installs have ~/Library/Application Support/Vertex
            // at 0755. Enforce 0700 through a no-follow directory descriptor so
            // a symlink cannot redirect chmod to another path.
            let dirFD = folder.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
            guard dirFD >= 0 else { return false }
            _ = fchmod(dirFD, 0o700)
            close(dirFD)
            // Created with 0600 from the start: the password is never on disk
            // with the umask-derived mode, not even for an instant.
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { return false }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                try handle.write(contentsOf: Data(value.utf8))
                try handle.synchronize()
                try handle.close()
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                return false
            }
            guard rename(temporary.path, url.path) == 0 else {
                try? FileManager.default.removeItem(at: temporary)
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
