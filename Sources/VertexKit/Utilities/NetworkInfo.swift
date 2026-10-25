import Darwin
import Foundation

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

    static func primaryIPv4Address() -> String? {
        var interfaces: [(name: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
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

            let name = String(cString: interface.ifa_name)
            guard !ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

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

            let ip = String(cString: host)
            // Skip link-local (169.254.x.x): not a usable LAN address.
            if !ip.isEmpty, !ip.hasPrefix("169.254.") {
                interfaces.append((name, ip))
            }
        }

        if let ethernet = interfaces.first(where: { $0.name == "en0" && isPrivate($0.address) }) {
            return ethernet.address
        }
        if let privateAddress = interfaces.first(where: { isPrivate($0.address) }) {
            return privateAddress.address
        }
        return interfaces.first?.address
    }
}
