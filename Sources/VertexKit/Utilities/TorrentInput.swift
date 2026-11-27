import Foundation

/// Shared validation for torrent input. Keeping the magnet/file rules in one
/// place prevents the drop, paste, open-panel and add paths from drifting.
package enum TorrentInput {
    package static func isMagnet(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("magnet:")
    }

    package static func isTorrentFile(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "torrent"
    }

    package static func isValidTrackerURL(_ raw: String) -> Bool {
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.utf8.count <= 2048 else {
            return false
        }
        for byte in candidate.utf8 {
            if byte <= 0x20 || byte == 0x7F {
                return false
            }
        }
        guard let delimiter = candidate.range(of: "://") else {
            return false
        }

        let scheme = candidate[..<delimiter.lowerBound]
        guard let first = scheme.unicodeScalars.first,
            (first >= "A" && first <= "Z") || (first >= "a" && first <= "z")
        else {
            return false
        }
        for scalar in scheme.unicodeScalars.dropFirst() {
            let isLetter = (scalar >= "A" && scalar <= "Z") || (scalar >= "a" && scalar <= "z")
            let isDigit = scalar >= "0" && scalar <= "9"
            let isSymbol = scalar == "+" || scalar == "-" || scalar == "."
            if !isLetter && !isDigit && !isSymbol {
                return false
            }
        }

        let rest = candidate[delimiter.upperBound...]
        let slashIndex = rest.firstIndex { $0 == "/" || $0 == "?" || $0 == "#" }
        let authority = slashIndex.map { rest[..<$0] } ?? rest
        guard !authority.isEmpty else {
            return false
        }

        let hostport: Substring
        if let atIndex = authority.lastIndex(of: "@") {
            hostport = authority[authority.index(after: atIndex)...]
        } else {
            hostport = authority
        }
        guard let hostFirst = hostport.first else {
            return false
        }

        if hostFirst == "[" {
            guard let close = hostport.firstIndex(of: "]"),
                close > hostport.index(after: hostport.startIndex)
            else {
                return false
            }
            let afterBracket = hostport[hostport.index(after: close)...]
            if afterBracket.isEmpty {
                return true
            }
            guard afterBracket.first == ":" else {
                return false
            }
            return isValidPortSlice(afterBracket.dropFirst())
        }

        if let colon = hostport.firstIndex(of: ":") {
            let host = hostport[..<colon]
            guard !host.isEmpty else {
                return false
            }
            return isValidPortSlice(hostport[hostport.index(after: colon)...])
        }
        return true
    }

    private static func isValidPortSlice(_ slice: Substring) -> Bool {
        guard !slice.isEmpty, slice.count <= 5 else {
            return false
        }
        var value = 0
        for byte in slice.utf8 {
            guard byte >= 0x30, byte <= 0x39 else {
                return false
            }
            value = value * 10 + Int(byte - 0x30)
        }
        return (1...65535).contains(value)
    }
}
