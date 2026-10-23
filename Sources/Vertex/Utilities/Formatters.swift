import Foundation

enum Fmt {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    static func bytes(_ value: Int64) -> String {
        let magnitude = Double(abs(value))
        if magnitude < 1000 {
            return "\(value) B"
        }

        var scaled = magnitude
        var unitIndex = 0
        while scaled >= 1000 && unitIndex < units.count - 1 {
            scaled /= 1000
            unitIndex += 1
        }

        let decimals = scaled < 10 ? 1 : (scaled < 100 ? 1 : 0)
        let format = "%.\(decimals)f"
        let number = String(format: format, locale: Locale.current, scaled)
        let sign = value < 0 ? "-" : ""
        return "\(sign)\(number) \(units[unitIndex])"
    }

    static func rate(_ bytesPerSecond: Int64) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    static func eta(_ seconds: Int64) -> String {
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

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", locale: Locale.current, min(max(fraction, 0), 1) * 100)
    }

    static func ratio(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale.current, value)
    }

    static func added(_ unix: Int64) -> String {
        guard unix > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func relativeDate(_ unix: Int64) -> String {
        guard unix > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
