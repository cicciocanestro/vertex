import Foundation

package enum Fmt {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    package static func bytes(_ value: Int64) -> String {
        let magnitude = Double(value.magnitude)
        if magnitude < 1000 {
            return "\(value) B"
        }

        var scaled = magnitude
        var unitIndex = 0
        while scaled >= 999.5 && unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }

        let decimals = scaled < 99.95 ? 1 : 0
        let format = "%.\(decimals)f"
        let number = String(format: format, locale: Locale.current, scaled)
        let sign = value < 0 ? "-" : ""
        return "\(sign)\(number) \(units[unitIndex])"
    }

    package static func rate(_ bytesPerSecond: Int64) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    package static func eta(_ seconds: Int64) -> String {
        guard seconds >= 0 else { return "—" }
        if seconds == 0 { return L("Completato") }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
        if seconds < 86_400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let dayUnit = L("g")
        return hours > 0 ? "\(days)\(dayUnit) \(hours)h" : "\(days)\(dayUnit)"
    }

    package static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        if fraction <= 0 { return "0%" }
        if fraction >= 1 { return "100%" }
        if fraction >= 0.995 {
            let capped = min((fraction * 1000).rounded() / 10, 99.9)
            return String(format: "%.1f%%", locale: Locale.current, capped)
        }
        return String(format: "%.0f%%", locale: Locale.current, fraction * 100)
    }

    package static func ratio(_ value: Double) -> String {
        let safe = value.isFinite ? max(value, 0) : 0
        return String(format: "%.2f", locale: Locale.current, safe)
    }
}
