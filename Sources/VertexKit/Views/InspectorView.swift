import SwiftUI

/// Counts shown as badges on the inspector tabs. The detail may not be loaded
/// yet, so a missing detail is zero rather than a spinner.
enum InspectorBadge {
    static func count(for tab: DetailTab, detail: TorrentDetail?) -> Int {
        guard let detail else { return 0 }
        switch tab {
        case .files: return detail.files.count
        case .peers: return detail.peers.count
        case .trackers: return detail.trackers.count
        }
    }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case files = "files"
    case peers = "peers"
    case trackers = "trackers"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .files: return L("File")
        case .peers: return L("Peer")
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
    @StateObject private var pendingAddedTrackers = UIState<[String]>([])
    @StateObject private var pendingRemovedTrackers = UIState<Set<String>>([])
    @StateObject private var isUpdatingTrackers = UIState(false)
    @StateObject private var trackerUnlockTask = UIState<Task<Void, Never>?>(nil)

    /// Detail matching `self.torrent`, or `nil` while the async load is in flight.
    private var currentDetail: TorrentDetail? {
        if let selectedID = engine.selectedID, selectedID != torrent.id {
            return nil
        }
        return engine.detail
    }

    init(
        engine: TorrentEngine,
        torrent: Torrent,
        initialTab: DetailTab = .files,
        onClose: @escaping () -> Void,
        onDeleteWithFiles: @escaping (Torrent) -> Void
    ) {
        _engine = ObservedObject(wrappedValue: engine)
        self.torrent = torrent
        _tab = StateObject(wrappedValue: UIState(initialTab))
        self.onClose = onClose
        self.onDeleteWithFiles = onDeleteWithFiles
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.right")
                        .font(Typography.captionMediumText)
                        .foregroundStyle(palette.tertiary)
                    Text(L("Dettagli"))
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
                    saveLocation(palette)
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
        .onChange(of: torrent.id) { _, _ in
            resetTrackerEditState()
        }
        .onChange(of: engine.detail) { _, _ in
            clearPendingTrackerMutation()
        }
        .onDisappear {
            trackerUnlockTask.value?.cancel()
            trackerUnlockTask.value = nil
        }
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
                        .foregroundStyle(palette.mutedText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(torrent.phase.label))
            } else {
                Text(torrent.phase.label)
                    .foregroundStyle(color)
            }
        }
        .font(Typography.microRoundedSemiboldText)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(torrent.phase == .paused ? palette.input : color.opacity(0.12)))
    }

    private func actions(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            if torrent.paused && !torrent.isQueued {
                Button {
                    engine.resume(torrent)
                } label: {
                    Label(L("Riprendi"), systemImage: "play.fill")
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
                    Label(L("Escludi"), systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                .help(L("Escludi dalla coda"))
            } else {
                Button {
                    engine.pause(torrent)
                } label: {
                    Label(L("Pausa"), systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
            }

            // Four identical circles were ~157 pt of chrome with no hierarchy
            // and gave the torrent name almost no room. The destructive and
            // rare actions move into a menu; pause/resume stays primary.
            Menu {
                Button {
                    engine.reveal(torrent)
                } label: {
                    Label(L("Mostra nel Finder"), systemImage: "folder")
                }

                Button {
                    engine.chooseAndMoveStorage(for: torrent)
                } label: {
                    Label(L("Sposta file…"), systemImage: "folder.badge.gearshape")
                }

                Button {
                    engine.copyMagnet(for: torrent)
                } label: {
                    Label(L("Copia link magnet"), systemImage: "link")
                }

                Divider()

                Button(role: .destructive) {
                    onDeleteWithFiles(torrent)
                } label: {
                    Label(L("Rimuovi"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .background(Circle().fill(palette.input))
            .overlay(Circle().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
            .help(L("Altre azioni"))
            .accessibilityLabel(Text(L("Altre azioni")))
        }
    }

    /// A healthy torrent never showed where its files live: the save path only
    /// appeared inside the error banner.
    private func saveLocation(_ palette: Palette) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(Typography.captionMediumText)
                .foregroundStyle(palette.tertiary)

            Text(torrent.savePath)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(torrent.savePath)

            Spacer(minLength: 4)

            IconButton(icon: "arrow.up.forward.square", help: "Mostra nel Finder", size: 22) {
                engine.reveal(torrent)
            }
        }
    }

    private func errorBanner(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Typography.captionText)
                Text(L("Errore del torrent"))
                    .font(Typography.smallSemiboldText)
            }
            .foregroundStyle(palette.coralText)

            Text(torrent.localizedError)
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
            statCell(
                "Download", Fmt.rate(torrent.downloadRate), palette,
                accent: torrent.downloadRate > 0 ? palette.mintText : nil)
            statCell(
                "Upload", Fmt.rate(torrent.uploadRate), palette,
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
        ) { option, _ in
            Text(option.label)
            let count = badgeCount(for: option)
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(Typography.microRoundedSemiboldText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
    }

    private func badgeCount(for tab: DetailTab) -> Int {
        guard let detail = currentDetail else { return 0 }
        if tab == .trackers {
            return effectiveTrackerURLs(from: detail).count
        }
        return InspectorBadge.count(for: tab, detail: detail)
    }

    @ViewBuilder
    private func tabContent(_ palette: Palette) -> some View {
        switch tab.value {
        case .files:
            filesContent(palette)
        case .peers:
            peersContent(palette)
        case .trackers:
            trackersContent(palette)
        }
    }

    @ViewBuilder
    private func filesContent(_ palette: Palette) -> some View {
        if !torrent.hasMetadata && !(currentDetail?.metadata ?? false) {
            waiting(palette, text: "In attesa dei metadati…")
        } else if let detail = currentDetail {
            if !detail.metadata {
                waiting(palette, text: "In attesa dei metadati…")
            } else if !detail.files.isEmpty {
                let files = detail.files
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
        } else {
            loadingDetail(palette)
        }
    }

    private func filesToolbar(files: [TorrentFile], palette: Palette) -> some View {
        let wantedCount = files.filter(\.isWanted).count
        let allWanted = wantedCount == files.count
        let noneWanted = wantedCount == 0

        return HStack(spacing: 6) {
            Text(
                wantedCount == 1
                    ? LF("%ld di %ld selezionato", wantedCount, files.count)
                    : LF("%ld di %ld selezionati", wantedCount, files.count)
            )
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

            if let detail = currentDetail {
                let visibleTrackers = detail.trackers.filter {
                    !pendingRemovedTrackers.value.contains($0.url.lowercased())
                }
                let addedURLs = pendingAddedTrackers.value
                if !visibleTrackers.isEmpty || !addedURLs.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleTrackers) { tracker in
                            trackerRow(tracker, palette)
                            if tracker.id != visibleTrackers.last?.id || !addedURLs.isEmpty {
                                Hairline(palette: palette)
                            }
                        }
                        ForEach(addedURLs, id: \.self) { url in
                            pendingTrackerRow(url, palette)
                            if url != addedURLs.last {
                                Hairline(palette: palette)
                            }
                        }
                    }
                } else {
                    waiting(palette, text: "Nessun tracker disponibile")
                }
            } else {
                loadingDetail(palette)
            }
        }
    }

    /// Tracker editor. The list is replaced as a whole (see
    /// `TorrentEngine.setTrackers`), so both actions below send the full list
    /// only once `currentDetail` is loaded and no tracker update is in flight.
    private func trackerEditor(_ palette: Palette) -> some View {
        let isEditable = currentDetail != nil && !isUpdatingTrackers.value
        return HStack(spacing: 6) {
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
                .disabled(!isEditable)
                .onSubmit { commitTracker() }

            Button(L("Aggiungi")) {
                commitTracker()
            }
            .buttonStyle(SmallButtonStyle())
            .disabled(!canAddTracker)
        }
    }

    private var trimmedNewTracker: String {
        TrackerInput.trimmed(newTracker.value)
    }

    private func effectiveTrackerURLs(from detail: TorrentDetail) -> [String] {
        let kept = detail.trackers.map(\.url).filter {
            !pendingRemovedTrackers.value.contains($0.lowercased())
        }
        return kept + pendingAddedTrackers.value
    }

    private var canAddTracker: Bool {
        guard let detail = currentDetail, !isUpdatingTrackers.value else { return false }
        return TrackerInput.canAdd(
            newTracker.value,
            existing: effectiveTrackerURLs(from: detail)
        )
    }

    private func commitTracker() {
        guard let detail = currentDetail, !isUpdatingTrackers.value else { return }
        let candidate = trimmedNewTracker
        let existing = effectiveTrackerURLs(from: detail)
        guard TrackerInput.canAdd(candidate, existing: existing) else { return }
        let urls = existing + [candidate]
        pendingAddedTrackers.value.append(candidate)
        beginTrackerMutation()
        engine.setTrackers(urls, torrentID: torrent.id)
        newTracker.value = ""
    }

    private func removeTracker(_ url: String) {
        guard let detail = currentDetail, !isUpdatingTrackers.value else { return }
        let lower = url.lowercased()
        let urls = effectiveTrackerURLs(from: detail).filter { $0.lowercased() != lower }
        pendingRemovedTrackers.value.insert(lower)
        pendingAddedTrackers.value.removeAll { $0.lowercased() == lower }
        beginTrackerMutation()
        engine.setTrackers(urls, torrentID: torrent.id)
    }

    private func beginTrackerMutation() {
        isUpdatingTrackers.value = true
        trackerUnlockTask.value?.cancel()
        let unlockTaskState = trackerUnlockTask
        let updatingState = isUpdatingTrackers
        let addedState = pendingAddedTrackers
        let removedState = pendingRemovedTrackers
        unlockTaskState.value = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            unlockTaskState.value = nil
            updatingState.value = false
            addedState.value = []
            removedState.value = []
        }
    }

    private func clearPendingTrackerMutation() {
        trackerUnlockTask.value?.cancel()
        trackerUnlockTask.value = nil
        isUpdatingTrackers.value = false
        pendingAddedTrackers.value = []
        pendingRemovedTrackers.value = []
    }

    private func resetTrackerEditState() {
        newTracker.value = ""
        clearPendingTrackerMutation()
    }

    private func trackerRow(_ tracker: TorrentTracker, _ palette: Palette) -> some View {
        let color: Color =
            tracker.verified
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
            .disabled(isUpdatingTrackers.value)
        }
        .padding(.vertical, 7)
    }

    private func pendingTrackerRow(_ url: String, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.amber)
                .frame(width: 5, height: 5)
                .padding(.top, 4)

            Text(url)
                .font(Typography.captionMonoMediumText)
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .layoutPriority(1)

            Spacer(minLength: 4)

            IconButton(icon: "xmark", help: "Rimuovi tracker", size: 20) {
                removeTracker(url)
            }
            .disabled(isUpdatingTrackers.value)
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func peersContent(_ palette: Palette) -> some View {
        if let detail = currentDetail {
            let peers = detail.peers
            if !peers.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(peers) { peer in
                        peerRow(peer, palette)
                        if peer.id != peers.last?.id {
                            Hairline(palette: palette)
                        }
                    }
                }
            } else {
                waiting(palette, text: "Nessun peer connesso")
            }
        } else {
            loadingDetail(palette)
        }
    }

    private func peerRow(_ peer: TorrentPeer, _ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let code = GeoIP.countryCode(forEndpoint: peer.endpoint) {
                    Text(verbatim: GeoIP.flag(for: code) ?? "")
                        .font(Typography.smallText)
                        .help(GeoIP.countryName(for: code))
                        .accessibilityLabel(Text(GeoIP.countryName(for: code)))
                } else if GeoIP.isLocalEndpoint(peer.endpoint) {
                    Image(systemName: "house.fill")
                        .font(Typography.captionSmallText)
                        .foregroundStyle(palette.tertiary)
                        .help(L("Rete locale"))
                        .accessibilityLabel(Text(L("Rete locale")))
                }

                Text(peer.client.isEmpty ? L("Handshake…") : peer.client)
                    .font(Typography.smallMediumText)
                    .foregroundStyle(peer.client.isEmpty ? palette.tertiary : palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !peer.flags.isEmpty {
                    Text(verbatim: peer.flags)
                        .font(Typography.captionTinyMonoText)
                        .foregroundStyle(palette.mintText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.mint.opacity(0.11)))
                        .help(peerFlagsHelp(peer.flags))
                }

                if !peer.source.isEmpty {
                    Text(verbatim: peer.source)
                        .font(Typography.captionMicroSemiboldText)
                        .foregroundStyle(palette.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }

                Spacer(minLength: 4)

                Text(Fmt.percent(peer.progress))
                    .font(Typography.microRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            }

            HStack(spacing: 8) {
                Text(verbatim: peer.endpoint)
                    .font(Typography.captionTinyMonoText)
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer(minLength: 4)

                if peer.downloadRate > 0 {
                    SpeedText(value: peer.downloadRate, upload: false, compact: true)
                }
                if peer.uploadRate > 0 {
                    SpeedText(value: peer.uploadRate, upload: true, compact: true)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func peerFlagsHelp(_ flags: String) -> String {
        PeerFlagPresentation.description(for: flags)
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

    private func loadingDetail(_ palette: Palette) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(L("In attesa"))
                .font(Typography.smallText)
        }
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }

    private func priorityLabel(_ level: FilePriority) -> String {
        FilePriorityPresentation.label(level)
    }

    private func priorityIcon(_ level: FilePriority) -> String {
        FilePriorityPresentation.symbolName(level)
    }

    private func priorityColor(_ level: FilePriority, _ palette: Palette) -> Color {
        switch level {
        case .skip: return palette.tertiary
        case .normal: return palette.mintText
        case .high: return palette.violetText
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
