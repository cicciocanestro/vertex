import AppKit
import SwiftUI

struct TorrentListView: View {
    let engine: TorrentEngine
    let torrents: [Torrent]
    let selectedIDs: Set<String>
    let onSelectClick: (Torrent, Bool, Bool) -> Void
    let onSelectAll: () -> Void
    let onDeleteSelection: ([Torrent]) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var listFocused: Bool
    @StateObject private var navigationHeadID = UIState<String?>(nil)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(torrents) { torrent in
                        let isSelected = selectedIDs.contains(torrent.id)
                        TorrentRow(
                            engine: engine,
                            torrent: torrent,
                            selected: isSelected,
                            multiSelectionCount: isSelected ? selectedIDs.count : 1,
                            onSelect: { command, shift in
                                navigationHeadID.value = torrent.id
                                onSelectClick(torrent, command, shift)
                                listFocused = true
                            },
                            onDeleteWithFiles: {
                                if isSelected && selectedIDs.count > 1 {
                                    onDeleteSelection(engine.selectedTorrents)
                                } else {
                                    onDeleteSelection([torrent])
                                }
                            }
                        )
                        .id(torrent.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .focusable()
            .focused($listFocused)
            // Keep arrow-key navigation without the large blue system focus
            // ring around the whole scroll area; the selected row is the focus
            // indicator.
            .focusEffectDisabled()
            .onMoveCommand { direction in
                move(direction, proxy: proxy)
            }
            .onCommand(#selector(NSStandardKeyBindingResponding.selectAll(_:))) {
                onSelectAll()
                listFocused = true
            }
        }
    }

    /// Up/Down moves the selection through the visible list (`⇧` extends the
    /// range from the anchor). The target row is scrolled into view without
    /// animating when Reduce Motion is enabled.
    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard direction == .up || direction == .down, !torrents.isEmpty else { return }
        let shift = (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift)
        let cursorID =
            (shift ? navigationHeadID.value : nil)
            ?? engine.selectedID
            ?? navigationHeadID.value
            ?? selectedIDs.first
        let current = torrents.firstIndex { $0.id == cursorID }
        guard
            let next = TorrentListNavigation.nextIndex(
                current: current,
                count: torrents.count,
                delta: direction == .up ? -1 : 1
            )
        else {
            return
        }
        if let current, current == next { return }

        let target = torrents[next]
        navigationHeadID.value = target.id
        onSelectClick(target, false, shift)
        listFocused = true
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            proxy.scrollTo(target.id, anchor: .center)
        }
    }
}

struct TorrentRow: View {
    let engine: TorrentEngine
    let torrent: Torrent
    let selected: Bool
    var multiSelectionCount: Int = 1
    let onSelect: (_ command: Bool, _ shift: Bool) -> Void
    let onDeleteWithFiles: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .font(Typography.rowTitleText)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if torrent.hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.microText)
                            .foregroundStyle(Theme.coral)
                            .help(torrent.localizedError)
                    }

                    if torrent.sequential {
                        Text(verbatim: "SEQ")
                            .font(Typography.badgeText)
                            .tracking(0.6)
                            .foregroundStyle(palette.violetText)
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
                            .font(Typography.rowMetaText)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if torrent.hasError {
                    Text(torrent.localizedError)
                        .font(Typography.microMediumText)
                        .foregroundStyle(palette.coralText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if wide.value {
                HStack(spacing: 14) {
                    metric(
                        icon: "internaldrive",
                        value: torrent.hasMetadata ? Fmt.bytes(torrent.size) : "—",
                        help: "Dimensione",
                        minWidth: 82,
                        palette: palette
                    )
                    if torrent.phase == .downloading {
                        metric(
                            icon: "hourglass",
                            value: Fmt.eta(torrent.eta),
                            help: "Tempo rimasto",
                            minWidth: 62,
                            palette: palette
                        )
                    } else if torrent.finished {
                        metric(
                            icon: "arrow.left.arrow.right",
                            value: "×" + Fmt.ratio(torrent.ratio),
                            help: "Rapporto",
                            minWidth: 62,
                            palette: palette
                        )
                    } else {
                        metric(
                            icon: "hourglass",
                            value: "—",
                            help: "Tempo rimasto",
                            minWidth: 62,
                            palette: palette
                        )
                    }
                    metric(
                        icon: "arrow.up.arrow.down.circle",
                        value: "\(torrent.peers) / \(torrent.seeds)",
                        help: "Peer / Seed",
                        minWidth: 66,
                        palette: palette
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
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
                        .font(Typography.captionMediumRoundedText)
                        .monospacedDigit()
                        .foregroundStyle(palette.violetText)
                        .help(L("Rapporto"))
                        .accessibilityLabel(
                            Text(LF("rapporto %@", Fmt.ratio(torrent.ratio)))
                        )
                }
            }
            .frame(minWidth: 88, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 1) {
                // A queued torrent is already stopped: the pause icon means
                // "leave the queue", the play icon "resume" (which re-queues it).
                IconButton(
                    icon: torrent.paused && !torrent.isQueued ? "play.fill" : "pause.fill",
                    help: torrent.isQueued
                        ? "Escludi dalla coda"
                        : (torrent.paused ? "Riprendi" : "Pausa"),
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
            // Hidden actions must leave the accessibility tree too: `.opacity(0)`
            // and `allowsHitTesting(false)` still let VoiceOver focus and press
            // buttons the user cannot see.
            .accessibilityHidden(!(hover.value || selected))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            // The progress track lives inside the card background so it is
            // clipped by the rounded corners. It is padded on the leading side
            // (14 pt padding + 42 pt ring + 13 pt spacing = 69 pt) so it sits
            // cleanly under the content area without crossing or cutting through
            // the progress ring. Drawn only while there is progress to show.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(backgroundFill(palette))
                .overlay(alignment: .bottom) {
                    if torrent.hasMetadata && torrent.displayProgress > 0 && torrent.displayProgress < 0.999 {
                        ProgressTrack(
                            progress: torrent.displayProgress,
                            color: palette.phaseAccent(torrent.phase)
                        )
                        .padding(.leading, 69)
                        .padding(.trailing, 16)
                        .padding(.bottom, 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.mint)
                    .frame(width: 3, height: 30)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor(palette), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(
            color: selected
                ? Theme.mint.opacity(0.12)
                : (scheme == .dark ? Color.clear : Color.black.opacity(0.03)),
            radius: selected ? 14 : 6,
            x: 0,
            y: selected ? 4 : 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(count: 2) {
            engine.reveal(torrent)
        }
        .onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            onSelect(flags.contains(.command), flags.contains(.shift))
        }
        .onHover { value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                hover.value = value
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selected)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 780
        } action: { value in
            if wide.value != value { wide.value = value }
        }
        .contextMenu {
            if selected && multiSelectionCount > 1 {
                let batch = engine.selectedTorrents
                Button(LF("Riprendi selezionati (%ld)", batch.count)) {
                    engine.resume(batch)
                }
                Button(LF("Metti in pausa selezionati (%ld)", batch.count)) {
                    engine.pause(batch)
                }
                Button(L("Annuncia ai tracker")) {
                    engine.reannounce(batch)
                }
                Divider()
                Button(LF("Rimuovi selezionati (%ld)…", batch.count)) {
                    onDeleteWithFiles()
                }
            } else {
                if torrent.isQueued {
                    Button(L("Avvia ora (ignora coda)")) {
                        engine.forceStart(torrent)
                    }
                }

                Button(L(torrent.isQueued ? "Escludi dalla coda" : (torrent.paused ? "Riprendi" : "Pausa"))) {
                    engine.togglePause(torrent)
                }

                Button(L("Annuncia ai tracker")) {
                    engine.reannounce(torrent)
                }

                Divider()

                Button(L("Copia link magnet")) {
                    engine.copyMagnet(for: torrent)
                }

                Button(L("Mostra nel Finder")) {
                    engine.reveal(torrent)
                }

                Button(L("Sposta file…")) {
                    engine.chooseAndMoveStorage(for: torrent)
                }

                Button(L(torrent.sequential ? "Disattiva download sequenziale" : "Download sequenziale")) {
                    engine.toggleSequential(torrent)
                }

                Divider()

                // Same confirmation flow as the row's trash button: removing a
                // torrent from the context menu used to happen immediately, with no
                // way to choose between keeping and deleting the files.
                Button(L("Rimuovi…")) {
                    onDeleteWithFiles()
                }
            }
        }
        // The row itself is the main object of the app: VoiceOver must hear its
        // state and progress, know when it is selected, and be able to pause or
        // remove it without a mouse. `children: .contain` keeps the visible
        // buttons in the tree instead of swallowing them.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityAction(named: Text(torrent.paused ? L("Riprendi") : L("Pausa"))) {
            engine.togglePause(torrent)
        }
        .accessibilityAction(named: Text(L("Rimuovi"))) {
            onDeleteWithFiles()
        }
    }

    private var accessibilityValueText: String {
        if torrent.hasMetadata {
            return "\(torrent.phase.label) · \(Fmt.percent(torrent.displayProgress))"
        }
        return torrent.phase.label
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
        // A 12% tint of the muted paused grey disappeared on the light card:
        // paused rows use the neutral input fill instead.
        .background(Capsule().fill(torrent.phase == .paused ? palette.input : color.opacity(0.12)))
    }

    /// Narrow layout: the pill carries the state, these are the remaining
    /// details. In wide layout, we preserve progress details for paused or queued unfinished torrents.
    private var metaDetails: String {
        if wide.value {
            if torrent.hasMetadata && !torrent.finished && torrent.size > 0 && torrent.downloaded > 0 {
                return LF(
                    "%@ di %@ · %@", Fmt.bytes(torrent.downloaded), Fmt.bytes(torrent.size),
                    Fmt.percent(torrent.displayProgress))
            }
            return ""
        }

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
        minWidth: CGFloat,
        palette: Palette
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Typography.badgeText)
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(Typography.captionMediumRoundedText)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: minWidth, alignment: .leading)
        .help(L(help))
    }

    private func backgroundFill(_ palette: Palette) -> Color {
        if selected {
            // On the light card a 10% mint wash was almost invisible: the
            // selection relied on a 1 pt border. The fill and the leading bar
            // now carry it, so it reads at a glance.
            return Theme.mint.opacity(scheme == .dark ? 0.11 : 0.16)
        }
        return hover.value ? palette.cardHover : palette.card
    }

    private func borderColor(_ palette: Palette) -> Color {
        if selected {
            return Theme.mint.opacity(scheme == .dark ? 0.45 : 0.60)
        }
        return hover.value ? palette.strokeStrong : palette.stroke
    }
}
