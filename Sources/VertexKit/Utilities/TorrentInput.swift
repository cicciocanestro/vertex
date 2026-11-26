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
        guard !candidate.isEmpty,
            candidate.utf8.count <= 2048,
            candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            let delimiter = candidate.range(of: "://")
        else {
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

        let authority = candidate[delimiter.upperBound...]
        guard let hostFirst = authority.first,
            hostFirst != "/", hostFirst != ":", hostFirst != "?", hostFirst != "#"
        else {
            return false
        }
        if hostFirst == "[" {
            guard let close = authority.firstIndex(of: "]"),
                close > authority.index(after: authority.startIndex)
            else {
                return false
            }
        }
        return true
    }
}
