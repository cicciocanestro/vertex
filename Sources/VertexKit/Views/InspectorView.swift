import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case files = "files"
    case trackers = "trackers"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .files: return L("File")
        case .trackers: return L("Tracker")
        }
    }
}

struct InspectorView: View {
    @ObservedObject var engine: TorrentEngine
    let torrent: Torrent
    let onClose: () -> Void
    let onDeleteWithFiles: (Torrent) -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var tab = UIState<DetailTab>(.files)
    @StateObject private var newTracker = UIState("")

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.right")
                        .font(Typography.captionMediumText)
                        .foregroundStyle(palette.tertiary)
                    Text("Dettagli")
                        .font(Typography.bodySemiboldText)
                        .foregroundStyle(palette.secondary)
                }

                Spacer()

                IconButton(icon: "xmark", help: "Chiudi", size: 24, action: onClose)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)

            Hairline(palette: palette)

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
    }

    private func overview(_ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ProgressRing(progress: torrent.displayProgress, phase: torrent.phase, size: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text(torrent.name)
                    .font(Typography.titleText)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    phasePill(palette)

                    Text(shortHash)
                        .font(Typography.captionTinyMonoText)
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func phasePill(_ palette: Palette) -> some View {
        let color = palette.phaseText(torrent.phase)

        return Group {
            if torrent.phase == .completedPaused {
                HStack(spacing: 3) {
                    Text(L("Completato"))
                        .foregroundStyle(color)
                    Text(L("· In pausa"))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
            } else {
                Text(torrent.phase.label)
                    .foregroundStyle(color)
            }
        }
        .font(Typography.microRoundedSemiboldText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private func actions(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            if torrent.paused && !torrent.isQueued {
                Button {
                    engine.resume(torrent)
                } label: {
                    Label("Riprendi", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
            } else if torrent.isQueued {
                Button {
                    engine.forceStart(torrent)
                } label: {
                    Label(L("Avvia ora"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .help(L("Avvia subito ignorando i limiti della coda"))

                Button {
                    engine.togglePause(torrent)
                } label: {
                    Label("Escludi", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                .help(L("Escludi dalla coda"))
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

            IconButton(icon: "folder.badge.gearshape", help: "Sposta file…", size: 34) {
                engine.chooseAndMoveStorage(for: torrent)
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
                    .font(Typography.captionText)
                Text("Errore del torrent")
                    .font(Typography.smallSemiboldText)
            }
            .foregroundStyle(palette.coralText)

            Text(torrent.error)
                .font(Typography.captionText)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(torrent.savePath)
                .font(Typography.captionTinyMonoText)
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
            statCell("Download", Fmt.rate(torrent.downloadRate), palette,
                     accent: torrent.downloadRate > 0 ? palette.mintText : nil)
            statCell("Upload", Fmt.rate(torrent.uploadRate), palette,
                     accent: torrent.uploadRate > 0 ? palette.violetText : nil)
            statCell("Peer / Seed", "\(torrent.peers) / \(torrent.seeds)", palette)
            statCell("Tempo rimasto", etaText, palette)
        }
    }

    /// ETA only makes sense for an active download: a finished/seeding torrent
    /// would otherwise show "Completato" under "Tempo rimasto".
    private var etaText: String {
        torrent.finished ? "—" : Fmt.eta(torrent.eta)
    }

    private func statCell(
        _ label: String,
        _ value: String,
        _ palette: Palette,
        accent: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            Text(value)
                .font(Typography.smallRoundedSemiboldText)
                .monospacedDigit()
                .foregroundStyle(accent ?? palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .vertexCard(palette, radius: 9)
    }

    private func tabs(_ palette: Palette) -> some View {
        SegmentedPicker(
            selection: $tab.value,
            palette: palette,
            height: 25,
            corner: 7,
            horizontalPadding: 2,
            verticalPadding: 2,
            font: Typography.smallMediumText
        ) { option, selected in
            Text(option.label)
            if option == .files, let count = engine.detail?.files.count, count > 0 {
                Text(verbatim: "\(count)")
                    .font(Typography.microRoundedSemiboldText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
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
            VStack(alignment: .leading, spacing: 6) {
                if files.count > 1 {
                    filesToolbar(files: files, palette: palette)
                }

                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        fileRow(file, palette)
                        if file.id != files.last?.id {
                            Hairline(palette: palette)
                                .padding(.leading, 22)
                        }
                    }
                }
            }
        } else {
            waiting(palette, text: "Nessun file disponibile")
        }
    }

    private func filesToolbar(files: [TorrentFile], palette: Palette) -> some View {
        let wantedCount = files.filter(\.isWanted).count
        let allWanted = wantedCount == files.count
        let noneWanted = wantedCount == 0

        return HStack(spacing: 6) {
            Text(LF("%ld di %ld selezionati", wantedCount, files.count))
                .font(Typography.captionText)
                .foregroundStyle(palette.tertiary)

            Spacer()

            Button(L("Tutti")) {
                engine.setAllFilePriorities(wanted: true, torrentID: torrent.id)
            }
            .buttonStyle(SmallButtonStyle())
            .disabled(allWanted)

            Button(L("Nessuno")) {
                engine.setAllFilePriorities(wanted: false, torrentID: torrent.id)
            }
            .buttonStyle(SmallButtonStyle())
            .disabled(noneWanted)
        }
        .padding(.bottom, 2)
    }

    private func fileRow(_ file: TorrentFile, _ palette: Palette) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(FilePriority.allCases, id: \.rawValue) { level in
                    Button {
                        engine.setFilePriority(file, priority: level, torrentID: torrent.id)
                    } label: {
                        if level == file.priorityLevel {
                            Label(priorityLabel(level), systemImage: "checkmark")
                        } else {
                            Text(priorityLabel(level))
                        }
                    }
                }
            } label: {
                Image(systemName: priorityIcon(file.priorityLevel))
                    .font(Typography.bodyLargeRegularText)
                    .foregroundStyle(priorityColor(file.priorityLevel, palette))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Priorità del file"))
            .accessibilityLabel(Text(L("Priorità del file")))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: fileTypeIcon(file.path))
                        .font(Typography.badgeText)
                        .foregroundStyle(palette.tertiary)

                    Text(fileName(file.path))
                        .font(Typography.smallMediumText)
                        .foregroundStyle(file.isWanted ? palette.text : palette.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)
                }

                // Nested files are only distinguishable by their folder: the
                // row used to show the last path component alone.
                let folder = fileFolder(file.path)
                if !folder.isEmpty {
                    Text(folder)
                        .font(Typography.captionTinyMonoText)
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if file.progress > 0 && file.progress < 1 {
                    HStack(spacing: 6) {
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

                        Text(Fmt.percent(file.progress))
                            .font(Typography.microRoundedText)
                            .monospacedDigit()
                            .foregroundStyle(palette.tertiary)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            Text(Fmt.bytes(file.size))
                .font(Typography.microRoundedText)
                .monospacedDigit()
                .foregroundStyle(palette.tertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func trackersContent(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            trackerEditor(palette)

            if let trackers = engine.detail?.trackers, !trackers.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(trackers) { tracker in
                        trackerRow(tracker, palette)
                        if tracker.id != trackers.last?.id {
                            Hairline(palette: palette)
                        }
                    }
                }
            } else {
                waiting(palette, text: "Nessun tracker disponibile")
            }
        }
    }

    /// Tracker editor. The list is replaced as a whole (see
    /// `TorrentEngine.setTrackers`), so both actions below send the full list.
    private func trackerEditor(_ palette: Palette) -> some View {
        HStack(spacing: 6) {
            TextField(L("Aggiungi tracker (URL)"), text: $newTracker.value)
                .textFieldStyle(.plain)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.text)
                .padding(.vertical, 4)
                .frame(minHeight: 24)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .onSubmit { commitTracker() }

            Button(L("Aggiungi")) {
                commitTracker()
            }
            .buttonStyle(SmallButtonStyle())
            .disabled(!canAddTracker)
        }
    }

    private var trimmedNewTracker: String {
        newTracker.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAddTracker: Bool {
        let candidate = trimmedNewTracker
        guard candidate.contains("://") else { return false }
        return !(engine.detail?.trackers.contains {
            $0.url.caseInsensitiveCompare(candidate) == .orderedSame
        } ?? false)
    }

    private func commitTracker() {
        guard canAddTracker else { return }
        let urls = (engine.detail?.trackers.map(\.url) ?? []) + [trimmedNewTracker]
        engine.setTrackers(urls, torrentID: torrent.id)
        newTracker.value = ""
    }

    private func removeTracker(_ url: String) {
        let urls = engine.detail?.trackers.map(\.url).filter { $0 != url } ?? []
        engine.setTrackers(urls, torrentID: torrent.id)
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
                    .font(Typography.captionMonoMediumText)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if !tracker.message.isEmpty {
                    Text(tracker.message)
                        .font(Typography.captionTinyText)
                        .foregroundStyle(palette.coralText)
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if tracker.peers >= 0 {
                Text(verbatim: "\(tracker.peers)")
                    .font(Typography.microRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiary)
            }

            IconButton(icon: "xmark", help: "Rimuovi tracker", size: 20) {
                removeTracker(tracker.url)
            }
        }
        .padding(.vertical, 7)
    }

    private func waiting(_ palette: Palette, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(Typography.captionMediumText)
            Text(L(text))
                .font(Typography.smallText)
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private func priorityLabel(_ level: FilePriority) -> String {
        switch level {
        case .skip: return L("Non scaricare")
        case .normal: return L("Normale")
        case .high: return L("Alta")
        }
    }

    private func priorityIcon(_ level: FilePriority) -> String {
        switch level {
        case .skip: return "circle"
        case .normal: return "checkmark.circle.fill"
        case .high: return "bolt.circle.fill"
        }
    }

    private func priorityColor(_ level: FilePriority, _ palette: Palette) -> Color {
        switch level {
        case .skip: return palette.tertiary
        case .normal: return Theme.mint
        case .high: return Theme.violet
        }
    }

    private func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func fileFolder(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    private func fileTypeIcon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mkv", "mp4", "avi", "mov", "wmv", "m4v":
            return "film"
        case "mp3", "flac", "aac", "wav", "m4a", "ac3", "ogg":
            return "waveform"
        case "srt", "sub", "vtt", "txt", "nfo":
            return "doc.text"
        case "zip", "tar", "gz", "rar", "7z", "iso", "dmg":
            return "doc.zipper"
        case "jpg", "jpeg", "png", "webp", "gif":
            return "photo"
        default:
            return "doc"
        }
    }

    private var shortHash: String {
        guard torrent.id.count > 16 else { return torrent.id }
        return "\(torrent.id.prefix(8))…\(torrent.id.suffix(8))"
    }
}
