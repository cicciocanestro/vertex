import SwiftUI

struct TorrentListView: View {
    let engine: TorrentEngine
    let torrents: [Torrent]
    let selectedID: String?
    let onSelect: (Torrent) -> Void
    let onDeleteWithFiles: (Torrent) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(torrents) { torrent in
                    TorrentRow(
                        engine: engine,
                        torrent: torrent,
                        selected: selectedID == torrent.id,
                        onSelect: { onSelect(torrent) },
                        onDeleteWithFiles: { onDeleteWithFiles(torrent) }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }
}

struct TorrentRow: View {
    let engine: TorrentEngine
    let torrent: Torrent
    let selected: Bool
    let onSelect: () -> Void
    let onDeleteWithFiles: () -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = UIState(false)
    /// The extra columns only make sense when the row is wide enough; the
    /// row measures itself so opening the inspector hides them automatically.
    @StateObject private var wide = UIState(false)

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 13) {
            ProgressRing(progress: torrent.displayProgress, phase: torrent.phase, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(torrent.name)
                        .font(.system(size: 12.8, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if torrent.hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.micro)
                            .foregroundStyle(Theme.coral)
                            .help(torrent.error)
                    }

                    if torrent.sequential {
                        Text("SEQ")
                            .font(.system(size: 7.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.violet)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.violet.opacity(0.13)))
                    }
                }

                HStack(spacing: 6) {
                    phasePill(palette)

                    let details = metaDetails
                    if !details.isEmpty {
                        Text(details)
                            .font(.system(size: 10.3, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if torrent.hasError {
                    Text(torrent.error)
                        .font(Typography.microMedium)
                        .foregroundStyle(Theme.coral)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if wide.value {
                HStack(spacing: 14) {
                    metric(
                        icon: "externaldrive",
                        value: torrent.hasMetadata ? Fmt.bytes(torrent.size) : "—",
                        help: "Dimensione",
                        width: 82,
                        palette: palette
                    )
                    if torrent.phase == .downloading {
                        metric(
                            icon: "clock",
                            value: Fmt.eta(torrent.eta),
                            help: "Tempo rimasto",
                            width: 62,
                            palette: palette
                        )
                    } else if torrent.finished && torrent.ratio > 0 {
                        metric(
                            icon: "arrow.left.arrow.right",
                            value: "×" + Fmt.ratio(torrent.ratio),
                            help: "Rapporto",
                            width: 62,
                            palette: palette
                        )
                    } else {
                        metric(
                            icon: "clock",
                            value: "—",
                            help: "Tempo rimasto",
                            width: 62,
                            palette: palette
                        )
                    }
                    metric(
                        icon: "person.2",
                        value: "\(torrent.peers) / \(torrent.seeds)",
                        help: "Peer / Seed",
                        width: 66,
                        palette: palette
                    )
                }
            }

            VStack(alignment: .trailing, spacing: 3) {
                // Zero rates are the common case for seeds and paused rows:
                // repeating "0 B/s" on every row is pure noise. The column
                // keeps its width so the rows stay aligned.
                if torrent.downloadRate > 0 {
                    SpeedText(value: torrent.downloadRate, upload: false)
                }
                if torrent.uploadRate > 0 {
                    SpeedText(value: torrent.uploadRate, upload: true)
                }
                // For a finished torrent the ratio is the useful number, and
                // it used to live in the 10 pt meta line. Finished torrents
                // with no upload yet keep the column empty.
                if !wide.value && torrent.finished && torrent.ratio > 0 {
                    Text(verbatim: "×\(Fmt.ratio(torrent.ratio))")
                        .font(.system(size: 9.8, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.violet.opacity(0.9))
                        .help(L("Rapporto"))
                        .accessibilityLabel(
                            Text(verbatim: "\(L("Rapporto")) \(Fmt.ratio(torrent.ratio))")
                        )
                }
            }
            .frame(width: 88, alignment: .trailing)

            HStack(spacing: 1) {
                IconButton(
                    icon: torrent.paused ? "play.fill" : "pause.fill",
                    help: torrent.paused ? "Riprendi" : "Pausa",
                    size: 27
                ) {
                    engine.togglePause(torrent)
                }

                IconButton(icon: "folder", help: "Mostra nel Finder", size: 27) {
                    engine.reveal(torrent)
                }

                IconButton(icon: "trash", help: "Rimuovi", tint: hover.value ? Theme.coral : nil, size: 27) {
                    onDeleteWithFiles()
                }
            }
            .opacity(hover.value || selected ? 1 : 0)
            .allowsHitTesting(hover.value || selected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundFill(palette))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor(palette), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(
            color: selected ? Theme.mint.opacity(0.06) : .clear,
            radius: 14,
            x: 0,
            y: 4
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(count: 2) {
            engine.reveal(torrent)
        }
        .onTapGesture {
            onSelect()
        }
        .onHover { value in
            withAnimation(.easeOut(duration: 0.15)) {
                hover.value = value
            }
        }
        .animation(.snappy(duration: 0.18), value: selected)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width > 1180
        } action: { value in
            if wide.value != value { wide.value = value }
        }
        .contextMenu {
            Button(L(torrent.paused ? "Riprendi" : "Pausa")) {
                engine.togglePause(torrent)
            }

            Button("Annuncia ai tracker") {
                engine.reannounce(torrent)
            }

            Divider()

            Button("Copia link magnet") {
                engine.copyMagnet(for: torrent)
            }

            Button("Mostra nel Finder") {
                engine.reveal(torrent)
            }

            Button(L(torrent.sequential ? "Disattiva download sequenziale" : "Download sequenziale")) {
                engine.toggleSequential(torrent)
            }

            Divider()

            Button("Rimuovi") {
                engine.remove(torrent, deleteFiles: false)
            }

            Button("Rimuovi e cancella i file…", role: .destructive) {
                onDeleteWithFiles()
            }
        }
    }

    private func phasePill(_ palette: Palette) -> some View {
        let color: Color
        switch torrent.phase {
        case .downloading: color = Theme.mint
        case .metadata: color = Theme.amber
        case .checking: color = Theme.blue
        case .seeding: color = Theme.violet
        case .completed: color = Theme.green
        case .paused: color = Color.primary.opacity(0.5)
        }

        return Text(torrent.phase.label)
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    /// Narrow layout: the pill carries the state, these are the remaining
    /// details. Wide layout moves size/ETA/peers into dedicated columns.
    private var metaDetails: String {
        if wide.value { return "" }

        var parts: [String] = []
        if torrent.hasMetadata {
            if torrent.finished {
                parts.append(Fmt.bytes(torrent.size))
            } else {
                parts.append(LF("%@ di %@", Fmt.bytes(torrent.downloaded), Fmt.bytes(torrent.size)))
            }
        }

        if torrent.phase == .downloading {
            if torrent.downloadRate > 0 {
                parts.append(LF("ETA %@", Fmt.eta(torrent.eta)))
            }
            parts.append(LF("%ld peer", torrent.peers))
        }

        return parts.joined(separator: "  ·  ")
    }

    private func metric(
        icon: String,
        value: String,
        help: String,
        width: CGFloat,
        palette: Palette
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(value)
                .font(.system(size: 10.2, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(palette.tertiary)
        .frame(width: width, alignment: .leading)
        .help(L(help))
    }

    private func backgroundFill(_ palette: Palette) -> Color {
        if selected {
            return Theme.mint.opacity(scheme == .dark ? 0.075 : 0.1)
        }
        return hover.value ? palette.cardHover : palette.card
    }

    private func borderColor(_ palette: Palette) -> Color {
        if selected {
            return Theme.mint.opacity(0.32)
        }
        return hover.value ? palette.strokeStrong : palette.stroke
    }
}
