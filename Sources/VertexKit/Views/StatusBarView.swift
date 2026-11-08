import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: TorrentEngine
    var onOpenDiagnostics: () -> Void = {}

    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled
    @AppStorage(PrefKey.downloadLimitKB) private var downloadLimitKB = PrefDefault.downloadLimitKB
    @AppStorage(PrefKey.uploadLimitKB) private var uploadLimitKB = PrefDefault.uploadLimitKB

    @Environment(\.colorScheme) private var scheme

    /// Below this width the status bar drops the least essential groups
    /// (limits and torrent counters) instead of compressing the speed labels
    /// until they wrap onto a second line.
    private static let compactWidthThreshold: CGFloat = 1120
    @StateObject private var compactLayout = UIState(false)

    var body: some View {
        let palette = Palette(scheme: scheme)

        HStack(spacing: 13) {
            HStack(spacing: 7) {
                PulsingDot(color: dhtEnabled ? Theme.green : palette.tertiary)
                Text(dhtLabel)
                    .font(Typography.smallMedium)
                    .foregroundStyle(palette.secondary)
            }

            Hairline(palette: palette, axis: .vertical).frame(height: 14)

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

            if !compactLayout.value {
                if downloadLimitKB > 0 || uploadLimitKB > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 9, weight: .medium))
                        // Show the value the user typed in Settings. Converting it to
                        // bytes and formatting it with 1000-based units turned 150
                        // KB/s into "154 KB/s".
                        if downloadLimitKB > 0 {
                            Text(verbatim: "↓ \(downloadLimitKB) KB/s")
                        }
                        if uploadLimitKB > 0 {
                            Text(verbatim: "↑ \(uploadLimitKB) KB/s")
                        }
                    }
                    .font(.system(size: 9.6, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiary)
                }

                Text(LF("%ld attivi", engine.stats.active))
                    .font(Typography.smallMedium)
                    .foregroundStyle(palette.secondary)

                Text("·")
                    .foregroundStyle(palette.tertiary)

                Text(LF("%ld torrent", engine.torrents.count))
                    .font(Typography.smallMedium)
                    .foregroundStyle(palette.secondary)
            }

            Hairline(palette: palette, axis: .vertical).frame(height: 14)

            if engine.stats.isProxyActive {
                let hasProxyError = engine.stats.proxy.hasError
                HStack(spacing: 3) {
                    Image(systemName: hasProxyError ? "exclamationmark.shield.fill" : "shield.lefthalf.filled")
                        .font(Typography.captionMicroSemibold)
                    Text("SOCKS5")
                        .font(Typography.badge)
                }
                .foregroundStyle(hasProxyError ? Theme.coral : Theme.mint)
                .help(hasProxyError
                    ? LF("Proxy SOCKS5 non raggiungibile (%@:%ld): %@", engine.stats.proxy.hostname, engine.stats.proxy.port, engine.stats.proxy.error)
                    : LF("Proxy SOCKS5 attivo (%@:%ld)", engine.stats.proxy.hostname, engine.stats.proxy.port))

                Text("·")
                    .foregroundStyle(palette.tertiary)
            }

            Button(action: onOpenDiagnostics) {
                HStack(spacing: 4) {
                    Image(systemName: engine.stats.isBoundToAddress
                        ? "lock.shield.fill"
                        : "network")
                        .font(Typography.captionMicroSemibold)
                    Text(LF("Porta %ld", engine.stats.effectivePort))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(engine.stats.isListening ? palette.tertiary : Theme.coral)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(engine.stats.isBoundToAddress
                ? LF("Diagnostica rete · associato a %@", engine.stats.bindAddress)
                : L("Diagnostica rete"))
        }
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Hairline(palette: palette)
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width < Self.compactWidthThreshold
        } action: { compact in
            if compactLayout.value != compact {
                compactLayout.value = compact
            }
        }
    }

    private var dhtLabel: String {
        if !dhtEnabled { return L("DHT disattivato") }
        if engine.stats.dhtNodes > 0 { return LF("DHT · %ld nodi", engine.stats.dhtNodes) }
        return L("DHT · connessione")
    }

}
