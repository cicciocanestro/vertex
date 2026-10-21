import SwiftUI

struct TorrentListView: View {
    @ObservedObject var engine: TorrentEngine
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
    @ObservedObject var engine: TorrentEngine
    let torrent: Torrent
    let selected: Bool
    let onSelect: () -> Void
    let onDeleteWithFiles: () -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = UIState(false)

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
                            .font(.system(size: 9.5))
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

                Text(metaText)
                    .font(.system(size: 10.3, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if torrent.hasError {
                    Text(torrent.error)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.coral)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                SpeedText(value: torrent.downloadRate, upload: false)
                SpeedText(value: torrent.uploadRate, upload: true)
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
                    engine.remove(torrent, deleteFiles: false)
                }
            }
            .opacity(hover.value || selected ? 1 : 0)
            .allowsHitTesting(hover.value || selected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
        .contextMenu {
            Button(torrent.paused ? "Riprendi" : "Pausa") {
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

            Button(torrent.sequential ? "Disattiva download sequenziale" : "Download sequenziale") {
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

    private var metaText: String {
        var parts: [String] = []

        if torrent.hasMetadata {
            if torrent.finished {
                parts.append(Fmt.bytes(torrent.size))
            } else {
                parts.append("\(Fmt.bytes(torrent.downloaded)) di \(Fmt.bytes(torrent.size))")
            }
        }

        switch torrent.phase {
        case .paused:
            parts.append("In pausa")
        case .metadata:
            parts.append("Recupero metadati")
        case .checking:
            parts.append("Verifica in corso")
        case .downloading:
            if torrent.downloadRate > 0 {
                parts.append("ETA \(Fmt.eta(torrent.eta))")
            }
            parts.append("\(torrent.peers) peer")
        case .seeding:
            parts.append("In seed")
            parts.append("rapporto \(Fmt.ratio(torrent.ratio))")
        case .completed:
            parts.append("Completato")
        }

        if torrent.hasError {
            parts.append("Errore")
        }

        return parts.joined(separator: "  ·  ")
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
