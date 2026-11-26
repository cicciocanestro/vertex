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
        guard TorrentInput.isValidTrackerURL(candidate) else { return false }
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

package enum DiagnosticCheckStatus: Equatable {
    case ok
    case warning
    case error
    case info
}

package struct DiagnosticCheck: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let detail: String
    package let status: DiagnosticCheckStatus
}

/// Compact "is anything wrong?" summary for the diagnostics window. It does not
/// replace the detailed cards: it answers the first question a user asks.
package enum DiagnosticsChecklist {
    package static func checks(
        stats: SessionStats,
        upnpEnabled: Bool,
        dhtEnabled: Bool
    ) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []

        if stats.isListening {
            checks.append(
                DiagnosticCheck(
                    id: "listen",
                    title: L("Porta di ascolto"),
                    detail: "\(L("In ascolto")) · \(stats.effectivePort)",
                    status: .ok
                ))
        } else {
            let localizedListen = RuntimeErrorLocalizer.torrent(stats.listenError)
            checks.append(
                DiagnosticCheck(
                    id: "listen",
                    title: L("Porta di ascolto"),
                    detail: localizedListen.isEmpty ? L("Non in ascolto") : localizedListen,
                    status: .error
                ))
        }

        if let reason = DiagnosticsPresentation.upnpDisabledReason(
            isProxyActive: stats.isProxyActive,
            upnpEnabled: upnpEnabled
        ) {
            checks.append(
                DiagnosticCheck(
                    id: "mapping",
                    title: L("UPnP / NAT-PMP"),
                    detail: reason,
                    status: .info
                ))
        } else if stats.portmap.tcp.mapped || stats.portmap.udp.mapped {
            let mappedPort =
                stats.portmap.tcp.mapped
                ? stats.portmap.tcp.externalPort
                : stats.portmap.udp.externalPort
            checks.append(
                DiagnosticCheck(
                    id: "mapping",
                    title: L("UPnP / NAT-PMP"),
                    detail: String(
                        format: L("porta esterna %ld"),
                        mappedPort
                    ),
                    status: stats.portmap.hasError ? .warning : .ok
                ))
        } else if stats.portmap.hasError {
            checks.append(
                DiagnosticCheck(
                    id: "mapping",
                    title: L("UPnP / NAT-PMP"),
                    detail: L(
                        "Nessuna mappatura rilevata. Il router potrebbe avere UPnP/NAT-PMP disabilitato."
                    ),
                    status: .warning
                ))
        } else {
            checks.append(
                DiagnosticCheck(
                    id: "mapping",
                    title: L("UPnP / NAT-PMP"),
                    detail: L("non mappata"),
                    status: .warning
                ))
        }

        if !stats.proxy.enabled {
            checks.append(
                DiagnosticCheck(
                    id: "proxy",
                    title: L("Proxy SOCKS5"),
                    detail: L("Non configurato"),
                    status: .info
                ))
        } else if stats.proxy.hasError {
            checks.append(
                DiagnosticCheck(
                    id: "proxy",
                    title: L("Proxy SOCKS5"),
                    detail: stats.proxy.localizedError,
                    status: .error
                ))
        } else {
            checks.append(
                DiagnosticCheck(
                    id: "proxy",
                    title: L("Proxy SOCKS5"),
                    detail: L("Proxy attivo"),
                    status: .ok
                ))
        }

        if let reason = DiagnosticsPresentation.dhtDisabledReason(
            isProxyActive: stats.isProxyActive,
            dhtEnabled: dhtEnabled
        ) {
            checks.append(
                DiagnosticCheck(
                    id: "dht",
                    title: L("DHT"),
                    detail: reason,
                    status: .info
                ))
        } else if stats.dhtNodes > 0 {
            checks.append(
                DiagnosticCheck(
                    id: "dht",
                    title: L("DHT"),
                    detail: "\(L("Nodi DHT")): \(stats.dhtNodes)",
                    status: .ok
                ))
        } else {
            checks.append(
                DiagnosticCheck(
                    id: "dht",
                    title: L("DHT"),
                    detail: L("In attesa"),
                    status: .warning
                ))
        }

        return checks
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

    /// Why the DHT cannot run at all: either disabled by the SOCKS5 proxy to
    /// prevent clearnet DNS/UDP leaks, or turned off in Settings.
    package static func dhtDisabledReason(
        isProxyActive: Bool,
        dhtEnabled: Bool
    ) -> String? {
        if isProxyActive {
            return L("Disattivato dal proxy SOCKS5 per prevenire leak.")
        }
        if !dhtEnabled {
            return L("DHT disattivato")
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
