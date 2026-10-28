import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case files = "File"
    case trackers = "Tracker"

    var id: String { rawValue }
}

struct InspectorView: View {
    @ObservedObject var engine: TorrentEngine
    let torrent: Torrent
    let onClose: () -> Void
    let onDeleteWithFiles: (Torrent) -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var tab = UIState<DetailTab>(.files)

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.tertiary)
                    Text("Dettagli")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                }

                Spacer()

                IconButton(icon: "xmark", help: "Chiudi", size: 24, action: onClose)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            Rectangle()
                .fill(palette.stroke)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overview(palette)
                    actions(palette)
                    if torrent.hasError {
                        errorBanner(palette)
                    }
                    statsGrid(palette)
                    tabs(palette)
                    tabContent(palette)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity)
        .background(palette.panel)
        .overlay(alignment: .leading) {
            Hairline(palette: palette, axis: .vertical)
        }
    }

    private func overview(_ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ProgressRing(progress: torrent.displayProgress, phase: torrent.phase, size: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text(torrent.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    Text(torrent.phase.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }

                Text(shortHash)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private func actions(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            if torrent.paused {
                Button {
                    engine.resume(torrent)
                } label: {
                    Label("Riprendi", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    engine.pause(torrent)
                } label: {
                    Label("Pausa", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
            }

            IconButton(icon: "folder", help: "Mostra nel Finder", size: 34) {
                engine.reveal(torrent)
            }
            .background(Circle().fill(palette.input))
            .overlay(Circle().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))

            IconButton(icon: "link", help: "Copia link magnet", size: 34) {
                engine.copyMagnet(for: torrent)
            }
            .background(Circle().fill(palette.input))
            .overlay(Circle().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))

            IconButton(icon: "trash", help: "Rimuovi", tint: Theme.coral.opacity(0.85), size: 34) {
                onDeleteWithFiles(torrent)
            }
            .background(Circle().fill(palette.input))
            .overlay(Circle().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
        }
    }

    private func errorBanner(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("Errore del torrent")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(Theme.coral)

            Text(torrent.error)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(torrent.savePath)
                .font(.system(size: 8.8, design: .monospaced))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(torrent.savePath)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.coral.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.coral.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func statsGrid(_ palette: Palette) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            statCell("Dimensione", Fmt.bytes(torrent.size), palette)
            statCell("Scaricati", Fmt.bytes(torrent.downloaded), palette)
            statCell("Caricati", Fmt.bytes(torrent.uploaded), palette)
            statCell("Rapporto", Fmt.ratio(torrent.ratio), palette)
            statCell("Download", Fmt.rate(torrent.downloadRate), palette, accent: Theme.mint)
            statCell("Upload", Fmt.rate(torrent.uploadRate), palette, accent: Theme.violet)
            statCell("Peer / Seed", "\(torrent.peers) / \(torrent.seeds)", palette)
            statCell("Tempo rimasto", Fmt.eta(torrent.eta), palette)
        }
    }

    private func statCell(
        _ label: String,
        _ value: String,
        _ palette: Palette,
        accent: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ?? palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .vertexCard(palette, radius: 10)
    }

    private func tabs(_ palette: Palette) -> some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        tab.value = option
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(option.rawValue)
                        if option == .files, let count = engine.detail?.files.count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                    .font(.system(size: 10.5, weight: tab.value == option ? .semibold : .medium))
                    .foregroundStyle(tab.value == option ? palette.text : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab.value == option ? palette.cardHover : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private func tabContent(_ palette: Palette) -> some View {
        switch tab.value {
        case .files:
            filesContent(palette)
        case .trackers:
            trackersContent(palette)
        }
    }

    @ViewBuilder
    private func filesContent(_ palette: Palette) -> some View {
        if !(engine.detail?.metadata ?? torrent.hasMetadata) {
            waiting(palette, text: "In attesa dei metadati…")
        } else if let files = engine.detail?.files, !files.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    fileRow(file, palette)
                    if file.id != files.last?.id {
                        Rectangle()
                            .fill(palette.stroke)
                            .frame(height: 1)
                            .padding(.leading, 22)
                    }
                }
            }
        } else {
            waiting(palette, text: "Nessun file disponibile")
        }
    }

    private func fileRow(_ file: TorrentFile, _ palette: Palette) -> some View {
        HStack(spacing: 8) {
            Button {
                engine.setFilePriority(file, wanted: !file.isWanted, torrentID: torrent.id)
            } label: {
                Image(systemName: file.isWanted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(file.isWanted ? Theme.mint : palette.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L(file.isWanted ? "Non scaricare questo file" : "Scarica questo file"))

            VStack(alignment: .leading, spacing: 3) {
                Text(fileName(file.path))
                    .font(.system(size: 10.8, weight: .medium))
                    .foregroundStyle(file.isWanted ? palette.text : palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)

                if file.progress > 0 && file.progress < 1 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(Theme.mint.opacity(0.65))
                                .frame(width: geometry.size.width * file.progress)
                        }
                    }
                    .frame(height: 2.5)
                }
            }

            Spacer(minLength: 6)

            Text(Fmt.bytes(file.size))
                .font(.system(size: 9.3, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.tertiary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func trackersContent(_ palette: Palette) -> some View {
        if let trackers = engine.detail?.trackers, !trackers.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(trackers) { tracker in
                    trackerRow(tracker, palette)
                    if tracker.id != trackers.last?.id {
                        Rectangle()
                            .fill(palette.stroke)
                            .frame(height: 1)
                    }
                }
            }
        } else {
            waiting(palette, text: "Nessun tracker disponibile")
        }
    }

    private func trackerRow(_ tracker: TorrentTracker, _ palette: Palette) -> some View {
        let color: Color = tracker.verified
            ? Theme.green
            : (tracker.fails > 0 ? Theme.coral : Theme.amber)

        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(tracker.url)
                    .font(.system(size: 9.8, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if !tracker.message.isEmpty {
                    Text(tracker.message)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.coral.opacity(0.9))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if tracker.peers >= 0 {
                Text("\(tracker.peers)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiary)
            }
        }
        .padding(.vertical, 7)
    }

    private func waiting(_ palette: Palette, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 10, weight: .medium))
            Text(L(text))
                .font(.system(size: 10.5))
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private var shortHash: String {
        guard torrent.id.count > 16 else { return torrent.id }
        return "\(torrent.id.prefix(8))…\(torrent.id.suffix(8))"
    }
}
