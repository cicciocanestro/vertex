import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: TorrentEngine
    var onOpenDiagnostics: () -> Void = {}

    private var displayPort: Int {
        engine.stats.actualPort > 0 ? engine.stats.actualPort : engine.stats.port
    }

    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.downloadLimitKB) private var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) private var uploadLimitKB = PrefDefault.uploadLimitKB

    @Environment(\.colorScheme) private var scheme

    private var downloadLimitBytes: Int64 {
        Int64(Preferences.limitBytes(fromKB: downloadLimitKB))
    }

    private var uploadLimitBytes: Int64 {
        Int64(Preferences.limitBytes(fromKB: uploadLimitKB))
    }

    var body: some View {
        let palette = Palette(scheme: scheme)

        HStack(spacing: 13) {
            HStack(spacing: 7) {
                PulsingDot(color: dhtEnabled ? Theme.green : palette.tertiary)
                Text(dhtLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }

            divider(palette)

            HStack(spacing: 7) {
                SpeedText(value: engine.stats.downloadRate, upload: false)
                Sparkline(values: engine.downloadHistory, color: Theme.mint)
                    .frame(width: 88, height: 16)
            }

            HStack(spacing: 5) {
                SpeedText(value: engine.stats.uploadRate, upload: true)
                Sparkline(values: engine.uploadHistory, color: Theme.violet)
                    .frame(width: 52, height: 16)
                    .opacity(0.8)
            }

            Spacer(minLength: 10)

            if downloadLimitBytes > 0 || uploadLimitBytes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 9, weight: .medium))
                    if downloadLimitBytes > 0 {
                        Text("↓ \(Fmt.rate(downloadLimitBytes))")
                    }
                    if uploadLimitBytes > 0 {
                        Text("↑ \(Fmt.rate(uploadLimitBytes))")
                    }
                }
                .font(.system(size: 9.3, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.tertiary)
            }

            Text(LF("%ld attivi", engine.stats.active))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondary)

            Text("·")
                .foregroundStyle(palette.tertiary)

            Text(LF("%ld torrent", engine.torrents.count))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondary)

            divider(palette)

            Button(action: onOpenDiagnostics) {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(LF("Porta %ld", displayPort))
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(engine.stats.isListening ? palette.tertiary : Theme.coral)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Diagnostica rete")
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.stroke)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var dhtLabel: String {
        if !dhtEnabled { return L("DHT disattivato") }
        if engine.stats.dhtNodes > 0 { return LF("DHT · %ld nodi", engine.stats.dhtNodes) }
        return L("DHT · connessione")
    }

    private func divider(_ palette: Palette) -> some View {
        Rectangle()
            .fill(palette.stroke)
            .frame(width: 1, height: 14)
    }
}
