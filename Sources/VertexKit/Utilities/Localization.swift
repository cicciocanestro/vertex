import Foundation

/// Localized lookup for strings built at runtime.
/// `Text("...")`, `Button("...")` and similar SwiftUI literals are localized by SwiftUI itself;
/// use these helpers for computed strings, model labels, toasts and formatted messages.
package func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized formatted string. Use `%ld` for Int and `%@` for String arguments.
/// The POSIX format is intentional: counts and ports must not gain a thousands separator.
package func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

/// Translates common POSIX, libtorrent, SOCKS5 and UPnP/NAT-PMP runtime error
/// messages into the active UI language while leaving unknown details intact.
package enum RuntimeErrorLocalizer {
    package static func torrent(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if lower.contains("no space left on device") {
            return L("Spazio su disco insufficiente.")
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return L("Permesso negato.")
        }
        if lower.contains("no such file or directory") {
            return L("File o cartella non trovati.")
        }
        if lower.contains("read-only file system") {
            return L("Disco in sola lettura.")
        }
        if lower.contains("input/output error") || lower.contains("cross-device") {
            return L("Errore di lettura o scrittura sul disco.")
        }
        if lower.contains("collides with file from another torrent") {
            return L("Conflitto di file con un altro torrent.")
        }
        if lower.contains("hash check failed") || lower.contains("corrupt pieces") {
            return L("Verifica dati non riuscita (pezzi corrotti).")
        }
        if lower.contains("file too short") {
            return L("File incompleto o modificato esternamente.")
        }
        return value
    }

    package static func proxy(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if lower.contains("host proxy non valido") {
            return L("Host proxy non valido")
        }
        if lower.contains("porta proxy") {
            return L("Porta proxy non valida")
        }
        if lower.contains("authentication") || lower.contains("username required") {
            return L("Autenticazione SOCKS5 rifiutata")
        }
        if lower.contains("unsupported version") || lower.contains("command not supported") {
            return L("Protocollo SOCKS5 non supportato")
        }
        if lower.contains("general failure") {
            return L("Errore generale del proxy SOCKS5")
        }
        if lower.contains("connection refused") {
            return L("Connessione rifiutata")
        }
        if lower.contains("timed out") || lower == "timeout" {
            return L("Connessione fuori tempo massimo")
        }
        if lower.contains("unreachable") || lower.contains("no route to host") || lower.contains("host is down") {
            return L("Host non raggiungibile")
        }
        return value
    }

    package static func portmap(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        let prefix: String
        let body: String
        if let separator = value.range(of: ": ") {
            let head = String(value[..<separator.lowerBound])
            if head == "UPnP" || head == "NAT-PMP" {
                prefix = head + ": "
                body = String(value[separator.upperBound...])
            } else {
                prefix = ""
                body = value
            }
        } else {
            prefix = ""
            body = value
        }

        let lower = body.lowercased()
        let localizedBody: String
        if lower.contains("no router found") || lower.contains("no gateway") {
            localizedBody = L("nessun router compatibile rilevato")
        } else if lower.contains("not authorized") {
            localizedBody = L("non autorizzato (abilita NAT-PMP sul router)")
        } else if lower == "timeout" || lower.contains("timed out") {
            localizedBody = L("tempo scaduto")
        } else {
            localizedBody = body
        }
        return prefix + localizedBody
    }
}
