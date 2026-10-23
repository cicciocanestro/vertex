import Foundation

/// Localized lookup for strings built at runtime.
/// `Text("...")`, `Button("...")` and similar SwiftUI literals are localized by SwiftUI itself;
/// use these helpers for computed strings, model labels, toasts and formatted messages.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized formatted string. Use `%ld` for Int and `%@` for String arguments.
/// The POSIX format is intentional: counts and ports must not gain a thousands separator.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
