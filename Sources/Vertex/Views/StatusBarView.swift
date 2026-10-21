import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: TorrentEngine
    var onOpenDiagnostics: () -> Void = {}

    private var displayPort: Int {
        engine.stats.actualPort > 0 ? engine.stats.actualPort : engine.stats.port
    }

    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = true
    @AppStorage(PrefKey.downloadLimitKB) private var downloadLimitKB = 0
    @AppStorage(PrefKey.uploadLimitKB) private var uploadLimitKB = 0

    @Environment(\.colorScheme) private var scheme

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

            if downloadLimitKB > 0 || uploadLimitKB > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 9, weight: .medium))
                    if downloadLimitKB > 0 {
                        Text("↓ \(Fmt.rate(Int64(downloadLimitKB) * 1024))")
                    }
                    if uploadLimitKB > 0 {
                        Text("↑ \(Fmt.rate(Int64(uploadLimitKB) * 1024))")
                    }
                }
                .font(.system(size: 9.3, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.tertiary)
            }

            Text("\(engine.stats.active) attivi")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondary)

            Text("·")
                .foregroundStyle(palette.tertiary)

            Text("\(engine.torrents.count) torrent")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondary)

            divider(palette)

            Button(action: onOpenDiagnostics) {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("Porta \(displayPort)")
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
        if !dhtEnabled { return "DHT disattivato" }
        if engine.stats.dhtNodes > 0 { return "DHT · \(engine.stats.dhtNodes) nodi" }
        return "DHT · connessione"
    }

    private func divider(_ palette: Palette) -> some View {
        Rectangle()
            .fill(palette.stroke)
            .frame(width: 1, height: 14)
    }
}
