import Darwin
import Foundation

/// A local IPv4 address that the engine can be pinned to.
struct NetworkInterface: Identifiable, Hashable {
    let name: String
    let address: String

    var id: String { "\(name)/\(address)" }

    /// Name and address for the settings menu, e.g. `utun3 · 10.8.0.2`.
    var label: String { "\(name) · \(address)" }
}

enum LocalNetwork {
    /// Interfaces that are virtual, tunnels or Apple-internal: never the LAN address a router sees.
    private static let ignoredPrefixes = [
        "lo", "utun", "ipsec", "ppp", "bridge", "vmenet", "vmnet", "vnic",
        "awdl", "llw", "anpi", "ap", "gif", "stf", "docker", "veth"
    ]

    /// RFC 1918 private ranges only (172.16.0.0/12, not all of 172.*).
    private static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    private static func isLoopback(_ ip: String) -> Bool {
        ip == "::1" || ip.hasPrefix("127.")
    }

    private static func isLinkLocal(_ ip: String) -> Bool {
        ip.hasPrefix("169.254.")
    }

    /// Whether an IPv4 address is usable as a LAN or binding target: not
    /// loopback and not link-local. Both the binding menu and the diagnostics
    /// view apply this rule, so the two lists cannot drift apart.
    private static func isUsableLANAddress(_ ip: String) -> Bool {
        !isLoopback(ip) && !isLinkLocal(ip)
    }

    /// Physical interfaces first, then tunnels: the first entry is the one the
    /// user most likely wants when they are not looking for a VPN.
    private static func rank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("utun") { return 2 }
        return 3
    }

    /// Every usable IPv4 address, including the tunnel ones that
    /// `primaryIPv4Address()` hides. The settings menu binds the engine to one
    /// of these values, so this is the list of candidates.
    static func ipv4Interfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        let requiredFlags = UInt32(IFF_UP | IFF_RUNNING)

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & requiredFlags == requiredFlags else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = host.withUnsafeBufferPointer { ptr in
                ptr.baseAddress.map { String(cString: $0) } ?? ""
            }
            guard !ip.isEmpty, isUsableLANAddress(ip) else { continue }

            let name = String(cString: interface.ifa_name)
            guard !interfaces.contains(where: { $0.address == ip }) else { continue }
            interfaces.append(NetworkInterface(name: name, address: ip))
        }

        return interfaces.sorted {
            let lhs = rank($0.name)
            let rhs = rank($1.name)
            if lhs != rhs { return lhs < rhs }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.address < $1.address
        }
    }

    static func primaryIPv4Address() -> String? {
        let lanInterfaces = ipv4Interfaces().filter { interface in
            !ignoredPrefixes.contains(where: { interface.name.hasPrefix($0) })
        }

        if let ethernet = lanInterfaces.first(where: { $0.name == "en0" && isPrivate($0.address) }) {
            return ethernet.address
        }
        if let privateAddress = lanInterfaces.first(where: { isPrivate($0.address) }) {
            return privateAddress.address
        }
        return lanInterfaces.first?.address
    }
}
