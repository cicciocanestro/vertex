import Darwin
import Foundation

enum LocalNetwork {
    static func primaryIPv4Address() -> String? {
        var interfaces: [(name: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else { continue }

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
            if !ip.isEmpty {
                interfaces.append((name, ip))
            }
        }

        if let ethernet = interfaces.first(where: { $0.name == "en0" }) {
            return ethernet.address
        }
        if let privateAddress = interfaces.first(where: {
            $0.address.hasPrefix("192.168.")
                || $0.address.hasPrefix("10.")
                || $0.address.hasPrefix("172.")
        }) {
            return privateAddress.address
        }
        return interfaces.first?.address
    }
}
