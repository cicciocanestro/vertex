import Foundation

/// Pure presentation rules shared by the views. They live here so the logic can
/// be tested without rendering SwiftUI, and so the inspector and the
/// diagnostics window cannot drift apart.

package enum PeerFlagPresentation {
    /// Localized labels for libtorrent's peer flag string (`D`, `d`, `U`, …).
    /// Unknown characters are ignored: libtorrent may add flags in the future.
    package static func labels(for flags: String) -> [String] {
        var parts: [String] = []
        for character in flags {
            switch character {
            case "D": parts.append(L("Download attivo"))
            case "d": parts.append(L("In attesa di sblocco"))
            case "U": parts.append(L("Upload attivo"))
            case "u": parts.append(L("Richiede pezzi"))
            case "O": parts.append(L("Sblocco ottimistico"))
            case "S": parts.append(L("Seed completo"))
            case "I": parts.append(L("Connessione in ingresso"))
            case "P": parts.append(L("Trasporto uTP"))
            case "E": parts.append(L("Connessione cifrata"))
            default: break
            }
        }
        return parts
    }

    package static func description(for flags: String) -> String {
        labels(for: flags).joined(separator: " · ")
    }
}

package enum TrackerInput {
    package static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A tracker needs an explicit scheme and must not duplicate one already in
    /// the list; the comparison is case-insensitive like libtorrent's.
    package static func canAdd(_ raw: String, existing: [String]) -> Bool {
        let candidate = trimmed(raw)
        guard candidate.contains("://") else { return false }
        return !existing.contains {
            $0.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }
}

package enum FilePriorityPresentation {
    package static func label(_ level: FilePriority) -> String {
        switch level {
        case .skip: return L("Non scaricare")
        case .normal: return L("Normale")
        case .high: return L("Alta")
        }
    }

    package static func symbolName(_ level: FilePriority) -> String {
        switch level {
        case .skip: return "circle"
        case .normal: return "checkmark.circle.fill"
        case .high: return "bolt.circle.fill"
        }
    }
}

package enum DiagnosticsPresentation {
    /// Why UPnP/NAT-PMP cannot run at all. When this is non-nil the mapping rows
    /// must not look like a failure: the user disabled the feature, or the
    /// SOCKS5 proxy disabled it on purpose to avoid leaking the local IP.
    package static func upnpDisabledReason(
        isProxyActive: Bool,
        upnpEnabled: Bool
    ) -> String? {
        if isProxyActive {
            return L("Disattivato dal proxy SOCKS5 per prevenire leak.")
        }
        if !upnpEnabled {
            return L("Disattivato in Impostazioni → Rete.")
        }
        return nil
    }

    /// Port to probe from outside: the NAT-mapped external TCP port when there
    /// is one, otherwise the effective listen port.
    package static func reachabilityPort(
        tcp: PortMapInfo,
        effectivePort: Int
    ) -> Int {
        tcp.mapped && tcp.externalPort > 0 ? tcp.externalPort : effectivePort
    }
}
