import Foundation
import Security
import UserNotifications

/// Optional native macOS notifications for completed downloads.
///
/// `UNUserNotificationCenter` requires an `.app` bundle signed with a real
/// code-signing identity (Apple Development or Developer ID): calling it in a
/// CLI test runner crashes with an Objective-C exception, and ad-hoc bundles
/// are rejected by `usernoted`. Every entry point below checks the static code
/// signature first and degrades to a safe no-op until the bundle is signed.
package enum SystemNotifications {
    /// Cached once per launch: the bundle's code signature never changes while
    /// the process is running.
    package static let isBundleSignedWithIdentity: Bool = {
        if ProcessInfo.processInfo.processName == "VertexTestRunner" {
            return false
        }
        if ProcessInfo.processInfo.environment["VERTEX_NOTIFICATIONS_DISABLED"] == "1" {
            return false
        }
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier != nil else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }
        guard SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
            return false
        }

        var rawInfo: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawInfo
        )
        guard status == errSecSuccess,
              let info = rawInfo as? [String: Any],
              let flags = info[kSecCodeInfoFlags as String] as? UInt32 else {
            return false
        }
        let isAdhoc = (flags & SecCodeSignatureFlags.adhoc.rawValue) != 0
        return !isAdhoc
    }()

    package static func requestAuthorizationIfNeeded() {
        guard isBundleSignedWithIdentity else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    package static func postDownloadCompleted(names: [String]) {
        guard !names.isEmpty, isBundleSignedWithIdentity else { return }
        let title: String
        let body: String
        if names.count == 1, let first = names.first {
            title = L("Download completato")
            body = first
        } else {
            title = LF("%ld download completati", names.count)
            body = names.prefix(3).joined(separator: ", ")
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                enqueue(title: title, body: body)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    enqueue(title: title, body: body)
                }
            default:
                break
            }
        }
    }

    private static func enqueue(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vertex.completed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
