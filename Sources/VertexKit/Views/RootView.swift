import AppKit
import SwiftUI
import UniformTypeIdentifiers

package struct RootView: View {
    @ObservedObject private var engine: TorrentEngine

    package init() {
        self.engine = .shared
    }

    #if DEBUG
    package init(engine: TorrentEngine) {
        self.engine = engine
    }
    #endif

    @Environment(\.colorScheme) private var scheme

    @StateObject private var filter = UIState<TorrentFilter>(.all)
    @StateObject private var sort = UIState<TorrentSort>(.recent)
    @StateObject private var search = UIState("")
    @StateObject private var selectedID = UIState<String?>(nil)
    @StateObject private var showAddSheet = UIState(false)
    @StateObject private var addMode = UIState<AddTorrentMode>(.magnet)
    @StateObject private var showSettings = UIState(false)
    @StateObject private var showDiagnostics = UIState(false)
    @StateObject private var dropTargeted = UIState(false)
    @StateObject private var pendingDeletion = UIState<Torrent?>(nil)
    @StateObject private var showDeleteConfirmation = UIState(false)

    @FocusState private var searchFocused: Bool

    package var body: some View {
        layout
            .animation(.snappy(duration: 0.22), value: selectedID.value)
            .animation(.easeOut(duration: 0.18), value: engine.toast?.id)
            .animation(.snappy(duration: 0.22), value: showAddSheet.value)
            .animation(.snappy(duration: 0.22), value: showSettings.value)
            .animation(.snappy(duration: 0.22), value: showDiagnostics.value)
            .alert(
                "Rimuovere il torrent?",
                isPresented: $showDeleteConfirmation.value,
                presenting: pendingDeletion.value
            ) { torrent in
                Button("Rimuovi solo dalla lista") {
                    engine.remove(torrent, deleteFiles: false)
                    clearSelectionIfNeeded(torrent)
                }
                Button("Rimuovi e cancella i file", role: .destructive) {
                    engine.remove(torrent, deleteFiles: true)
                    clearSelectionIfNeeded(torrent)
                }
                Button("Annulla", role: .cancel) {}
            } message: { torrent in
                Text(LF("“%@”\nI file scaricati restano sul disco se scegli di rimuovere solo il torrent.", torrent.name))
            }
            .sheet(isPresented: $showAddSheet.value) {
                AddTorrentSheet(
                    engine: engine,
                    initialMode: addMode.value,
                    onClose: { showAddSheet.value = false }
                )
            }
            .modifier(
                RootEventHandlers(
                    onAddFile: chooseTorrentFile,
                    onAddMagnet: {
                        addMode.value = .magnet
                        showAddSheet.value = true
                    },
                    onPasteMagnet: pasteMagnet,
                    onPauseResume: {
                        guard !hasModalOverlay else { return }
                        togglePauseSelected()
                    },
                    onRemove: {
                        guard !hasModalOverlay else { return }
                        guard let torrent = selectedTorrent else {
                            engine.showToast(L("Seleziona un torrent"), kind: .info)
                            return
                        }
                        requestDeletion(torrent)
                    },
                    onReveal: {
                        guard !hasModalOverlay else { return }
                        if let torrent = selectedTorrent {
                            engine.reveal(torrent)
                        }
                    },
                    onCopyMagnet: {
                        guard !hasModalOverlay else { return }
                        if let torrent = selectedTorrent {
                            engine.copyMagnet(for: torrent)
                        }
                    },
                    onFind: { searchFocused = true },
                    onToggleInspector: {
                        guard !hasModalOverlay else { return }
                        toggleInspector()
                    },
                    onSettings: {
                        showDiagnostics.value = false
                        showSettings.value = true
                    },
                    onDiagnostics: {
                        showSettings.value = false
                        showDiagnostics.value = true
                    },
                    onFilter: { raw in
                        guard let value = TorrentFilter(rawValue: raw) else { return }
                        withAnimation(.snappy(duration: 0.18)) {
                            filter.value = value
                        }
                    }
                )
            )
            .onDrop(of: [.fileURL, .text], isTargeted: $dropTargeted.value) { providers in
                handleRootDrop(providers)
            }
            .onChange(of: engine.torrents) { _, torrents in
                if let id = selectedID.value, !torrents.contains(where: { $0.id == id }) {
                    selectedID.value = nil
                    engine.select(nil)
                }
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.environment["VERTEX_DEMO_SELECT"] == "1" {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if selectedID.value == nil, let first = engine.torrents.first {
                            select(first)
                        }
                    }
                }

                switch ProcessInfo.processInfo.environment["VERTEX_DEMO_SHEET"] {
                case "add":
                    addMode.value = .magnet
                    showAddSheet.value = true
                case "settings":
                    showSettings.value = true
                case "diagnostics":
                    showDiagnostics.value = true
                default:
                    break
                }
            }
            #endif
    }

    private var layout: some View {
        ZStack(alignment: .bottom) {
            AmbientBackground()
            mainColumn
            dropLayer
            modalLayer
            toastLayer
        }
    }

    @ViewBuilder
    private var modalLayer: some View {
        if showDiagnostics.value {
            modalBackdrop {
                NetworkDiagnosticsView(
                    engine: engine,
                    onClose: { showDiagnostics.value = false },
                    onOpenSettings: {
                        showDiagnostics.value = false
                        showSettings.value = true
                    }
                )
                .onExitCommand { showDiagnostics.value = false }
            }
        } else if showSettings.value {
            modalBackdrop {
                SettingsSheet(
                    engine: engine,
                    onClose: { showSettings.value = false },
                    onOpenDiagnostics: {
                        showSettings.value = false
                        showDiagnostics.value = true
                    }
                )
                .onExitCommand { showSettings.value = false }
            }
        }
    }

    private func modalBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Color.black
                .opacity(scheme == .dark ? 0.42 : 0.18)
                .ignoresSafeArea()

            content()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Palette(scheme: scheme).strokeStrong, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(0.42), radius: 45, x: 0, y: 20)
                .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .zIndex(3)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerBar
            filterBar

            HStack(spacing: 0) {
                content(Palette(scheme: scheme))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let torrent = selectedTorrent {
                    inspector(for: torrent)
                }
            }
            .clipped()

            StatusBarView(
                engine: engine,
                onOpenDiagnostics: { showDiagnostics.value = true }
            )
        }
    }

    private var headerBar: some View {
        HeaderBar(
            engine: engine,
            search: $search.value,
            searchFocused: $searchFocused,
            onAdd: openAddSheet,
            onAddFile: chooseTorrentFile,
            onSettings: { showSettings.value = true }
        )
    }

    private var filterBar: some View {
        FilterBar(
            filter: $filter.value,
            sort: $sort.value,
            torrents: engine.torrents
        )
    }

    private func inspector(for torrent: Torrent) -> some View {
        InspectorView(
            engine: engine,
            torrent: torrent,
            onClose: { select(nil) },
            onDeleteWithFiles: { requestDeletion($0) }
        )
        .frame(width: 350)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = engine.toast {
            ToastView(toast: toast) {
                engine.dismissToast()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 52)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(4)
        }
    }

    @ViewBuilder
    private var dropLayer: some View {
        if dropTargeted.value {
            DropOverlay()
                .zIndex(2)
        }
    }

    @ViewBuilder
    private func content(_ palette: Palette) -> some View {
        if engine.torrents.isEmpty && search.value.isEmpty {
            EmptyStateView(
                onAdd: openAddSheet,
                onPasteMagnet: pasteMagnet
            )
        } else if filteredTorrents.isEmpty {
            NoResultsView(query: search.value) {
                search.value = ""
                filter.value = .all
            }
        } else {
            TorrentListView(
                engine: engine,
                torrents: filteredTorrents,
                selectedID: selectedID.value,
                onSelect: { select($0) },
                onDeleteWithFiles: { requestDeletion($0) }
            )
        }
    }

    private var selectedTorrent: Torrent? {
        guard let id = selectedID.value else { return nil }
        return engine.torrents.first { $0.id == id }
    }

    /// Settings, diagnostics and the add sheet are app-modal: torrent shortcuts must not
    /// act on the list behind them.
    private var hasModalOverlay: Bool {
        showAddSheet.value || showSettings.value || showDiagnostics.value
    }

    private var filteredTorrents: [Torrent] {
        var list = engine.torrents.filter { filter.value.matches($0) }

        if !search.value.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search.value) ||
                $0.id.localizedCaseInsensitiveContains(search.value)
            }
        }

        switch sort.value {
        case .recent:
            list.sort { $0.added > $1.added }
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { $0.size > $1.size }
        case .progress:
            list.sort { $0.displayProgress > $1.displayProgress }
        case .speed:
            list.sort { $0.downloadRate > $1.downloadRate }
        }

        return list
    }

    private func openAddSheet() {
        addMode.value = .magnet
        showAddSheet.value = true
    }

    private func select(_ torrent: Torrent?) {
        selectedID.value = torrent?.id
        engine.select(torrent?.id)
    }

    private func requestDeletion(_ torrent: Torrent) {
        pendingDeletion.value = torrent
        showDeleteConfirmation.value = true
    }

    private func clearSelectionIfNeeded(_ torrent: Torrent) {
        if selectedID.value == torrent.id {
            selectedID.value = nil
            engine.select(nil)
        }
    }

    private func togglePauseSelected() {
        guard let torrent = selectedTorrent else {
            engine.showToast(L("Seleziona un torrent"), kind: .info)
            return
        }
        engine.togglePause(torrent)
    }

    private func toggleInspector() {
        if selectedID.value != nil {
            select(nil)
        } else if let first = filteredTorrents.first {
            select(first)
        }
    }

    private func pasteMagnet() {
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let clipboard, clipboard.lowercased().hasPrefix("magnet:") else {
            engine.showToast(L("Nessun link magnet negli appunti"), kind: .info)
            addMode.value = .magnet
            showAddSheet.value = true
            return
        }

        let paused = UserDefaults.standard.bool(forKey: PrefKey.startPaused)
        let sequential = UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault)
        _ = engine.addMagnet(
            clipboard,
            destination: nil,
            startPaused: paused,
            sequential: sequential
        )
    }

    private func chooseTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Aggiungi")
        if let type = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK else { return }

        let paused = UserDefaults.standard.bool(forKey: PrefKey.startPaused)
        let sequential = UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault)
        for url in panel.urls {
            _ = engine.addTorrentFile(
                url,
                destination: nil,
                startPaused: paused,
                sequential: sequential
            )
        }
    }

    private func handleRootDrop(_ providers: [NSItemProvider]) -> Bool {
        if showAddSheet.value || showSettings.value || showDiagnostics.value {
            return false
        }

        let paused = UserDefaults.standard.bool(forKey: PrefKey.startPaused)
        let sequential = UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault)
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in
                        _ = TorrentEngine.shared.addTorrentFile(
                            url,
                            destination: nil,
                            startPaused: paused,
                            sequential: sequential
                        )
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String,
                          text.lowercased().hasPrefix("magnet:") else { return }
                    Task { @MainActor in
                        _ = TorrentEngine.shared.addMagnet(
                            text,
                            destination: nil,
                            startPaused: paused,
                            sequential: sequential
                        )
                    }
                }
            }
        }

        return handled
    }
}


private struct RootEventHandlers: ViewModifier {
    let onAddFile: () -> Void
    let onAddMagnet: () -> Void
    let onPasteMagnet: () -> Void
    let onPauseResume: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onCopyMagnet: () -> Void
    let onFind: () -> Void
    let onToggleInspector: () -> Void
    let onSettings: () -> Void
    let onDiagnostics: () -> Void
    let onFilter: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .vertexAddFile)) { _ in onAddFile() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexAddMagnet)) { _ in onAddMagnet() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexPasteMagnet)) { _ in onPasteMagnet() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexPauseResume)) { _ in onPauseResume() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexRemove)) { _ in onRemove() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexReveal)) { _ in onReveal() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexCopyMagnet)) { _ in onCopyMagnet() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexFind)) { _ in onFind() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexToggleInspector)) { _ in onToggleInspector() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexSettings)) { _ in onSettings() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexDiagnostics)) { _ in onDiagnostics() }
            .onReceive(NotificationCenter.default.publisher(for: .vertexFilter)) { note in
                if let raw = note.object as? String {
                    onFilter(raw)
                }
            }
    }
}
