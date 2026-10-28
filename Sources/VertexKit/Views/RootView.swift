import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Mutually exclusive modal surfaces. Keeping them in one value makes invalid
/// combinations (for example settings and diagnostics both open) impossible.
enum ActiveModal: Equatable {
    case add(AddTorrentMode)
    case settings
    case diagnostics
}

package struct RootView: View {
    @ObservedObject private var engine: TorrentEngine

    package init() {
        self.engine = .shared
    }

    #if DEBUG
    /// Test-only initializer: lets the rendering tests start from a specific UI
    /// state (selected torrent, active modal, search query) without driving the
    /// view through AppKit. Production always uses `init()`.
    @MainActor
    init(
        engine: TorrentEngine,
        filter: TorrentFilter = .all,
        sort: TorrentSort = .recent,
        search: String = "",
        selectedID: String? = nil,
        showAddSheet: Bool = false,
        addMode: AddTorrentMode = .magnet,
        showSettings: Bool = false,
        showDiagnostics: Bool = false,
        dropTargeted: Bool = false,
        pendingDeletion: Torrent? = nil,
        showDeleteConfirmation: Bool = false
    ) {
        self.engine = engine
        engine.select(selectedID)
        let modal: ActiveModal?
        if showDiagnostics {
            modal = .diagnostics
        } else if showSettings {
            modal = .settings
        } else if showAddSheet {
            modal = .add(addMode)
        } else {
            modal = nil
        }
        _filter = StateObject(wrappedValue: UIState(filter))
        _sort = StateObject(wrappedValue: UIState(sort))
        _search = StateObject(wrappedValue: UIState(search))
        _activeModal = StateObject(wrappedValue: UIState(modal))
        _dropTargeted = StateObject(wrappedValue: UIState(dropTargeted))
        _pendingDeletion = StateObject(wrappedValue: UIState(pendingDeletion))
        _showDeleteConfirmation = StateObject(wrappedValue: UIState(showDeleteConfirmation))
    }
    #endif

    @Environment(\.colorScheme) private var scheme

    @StateObject private var filter = UIState<TorrentFilter>(.all)
    @StateObject private var sort = UIState<TorrentSort>(.recent)
    @StateObject private var search = UIState("")
    @StateObject private var activeModal = UIState<ActiveModal?>(nil)
    @StateObject private var dropTargeted = UIState(false)
    @StateObject private var pendingDeletion = UIState<Torrent?>(nil)
    @StateObject private var showDeleteConfirmation = UIState(false)

    @FocusState private var searchFocused: Bool

    package var body: some View {
        layout
            .animation(.snappy(duration: 0.22), value: engine.selectedID)
            .animation(.easeOut(duration: 0.18), value: engine.toast?.id)
            .animation(.snappy(duration: 0.22), value: activeModal.value)
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
            .sheet(isPresented: addSheetPresented) {
                AddTorrentSheet(
                    engine: engine,
                    initialMode: addMode,
                    onClose: { activeModal.value = nil }
                )
            }
            .modifier(
                RootEventHandlers(actions: RootEventHandlerActions(
                    onAddFile: chooseTorrentFile,
                    onAddMagnet: {
                        activeModal.value = .add(.magnet)
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
                        activeModal.value = .settings
                    },
                    onDiagnostics: {
                        activeModal.value = .diagnostics
                    },
                    onFilter: { raw in
                        guard let value = TorrentFilter(rawValue: raw) else { return }
                        withAnimation(.snappy(duration: 0.18)) {
                            filter.value = value
                        }
                    }
                ))
            )
            .onDrop(of: [.fileURL, .text], isTargeted: $dropTargeted.value) { providers in
                handleRootDrop(providers)
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.environment["VERTEX_DEMO_SELECT"] == "1" {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if engine.selectedID == nil, let first = engine.torrents.first {
                            select(first)
                        }
                    }
                }

                switch ProcessInfo.processInfo.environment["VERTEX_DEMO_SHEET"] {
                case "add":
                    activeModal.value = .add(.magnet)
                case "settings":
                    activeModal.value = .settings
                case "diagnostics":
                    activeModal.value = .diagnostics
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
        if case .diagnostics = activeModal.value {
            modalBackdrop {
                NetworkDiagnosticsView(
                    engine: engine,
                    onClose: { activeModal.value = nil },
                    onOpenSettings: { activeModal.value = .settings }
                )
                .onExitCommand { activeModal.value = nil }
            }
        } else if case .settings = activeModal.value {
            modalBackdrop {
                SettingsSheet(
                    engine: engine,
                    onClose: { activeModal.value = nil },
                    onOpenDiagnostics: { activeModal.value = .diagnostics }
                )
                .onExitCommand { activeModal.value = nil }
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
        let result = listResult
        let visible = result.torrents
        return VStack(spacing: 0) {
            headerBar
            filterBar(counts: result.counts)

            HStack(spacing: 0) {
                content(torrents: visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let torrent = selectedTorrent {
                    inspector(for: torrent)
                }
            }
            .clipped()

            StatusBarView(
                engine: engine,
                onOpenDiagnostics: { activeModal.value = .diagnostics }
            )
        }
    }

    private var headerBar: some View {
        HeaderBar(
            engine: engine,
            search: $search.value,
            searchFocused: $searchFocused,
            onAdd: openAddSheet,
            onSettings: { activeModal.value = .settings }
        )
    }

    private func filterBar(counts: [TorrentFilter: Int]) -> some View {
        FilterBar(
            filter: $filter.value,
            sort: $sort.value,
            counts: counts
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
    private func content(torrents: [Torrent]) -> some View {
        if engine.torrents.isEmpty && search.value.isEmpty {
            EmptyStateView(
                onAdd: openAddSheet,
                onPasteMagnet: pasteMagnet
            )
        } else if torrents.isEmpty {
            NoResultsView(query: search.value) {
                search.value = ""
                filter.value = .all
            }
        } else {
            TorrentListView(
                engine: engine,
                torrents: torrents,
                selectedID: engine.selectedID,
                onSelect: { select($0) },
                onDeleteWithFiles: { requestDeletion($0) }
            )
        }
    }

    private var selectedTorrent: Torrent? {
        guard let id = engine.selectedID else { return nil }
        return engine.torrent(withID: id)
    }

    /// Settings, diagnostics and the add sheet are app-modal: torrent shortcuts must not
    /// act on the list behind them.
    private var hasModalOverlay: Bool {
        activeModal.value != nil
    }

    private var listResult: TorrentListResult {
        TorrentListPipeline.applyWithCounts(
            to: engine.torrents,
            filter: filter.value,
            search: search.value,
            sort: sort.value
        )
    }

    private var addSheetPresented: Binding<Bool> {
        Binding(
            get: {
                if case .add = activeModal.value { return true }
                return false
            },
            set: { presented in
                if !presented { activeModal.value = nil }
            }
        )
    }

    private var addMode: AddTorrentMode {
        if case .add(let mode) = activeModal.value { return mode }
        return .magnet
    }

    private func openAddSheet() {
        activeModal.value = .add(.magnet)
    }

    private func select(_ torrent: Torrent?) {
        engine.select(torrent?.id)
    }

    private func requestDeletion(_ torrent: Torrent) {
        pendingDeletion.value = torrent
        showDeleteConfirmation.value = true
    }

    private func clearSelectionIfNeeded(_ torrent: Torrent) {
        if engine.selectedID == torrent.id {
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
        if engine.selectedID != nil {
            select(nil)
        } else if let first = listResult.torrents.first {
            select(first)
        }
    }

    private func pasteMagnet() {
        let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let clipboard, TorrentInput.isMagnet(clipboard) else {
            engine.showToast(L("Nessun link magnet negli appunti"), kind: .info)
            activeModal.value = .add(.magnet)
            return
        }

        let paused = Preferences.startPaused
        let sequential = Preferences.sequentialDefault
        _ = engine.addMagnet(
            clipboard,
            destination: nil,
            startPaused: paused,
            sequential: sequential
        )
    }

    private func chooseTorrentFile() {
        let panel = OpenPanelFactory.torrent(
            allowMultiple: true,
            prompt: L("Aggiungi")
        )

        guard panel.runModal() == .OK else { return }

        let paused = Preferences.startPaused
        let sequential = Preferences.sequentialDefault
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
        if activeModal.value != nil {
            return false
        }

        let paused = Preferences.startPaused
        let sequential = Preferences.sequentialDefault

        return TorrentDropHandler.handle(providers) { item in
            Task { @MainActor in
                switch item {
                case .torrent(let url):
                    _ = engine.addTorrentFile(
                        url,
                        destination: nil,
                        startPaused: paused,
                        sequential: sequential
                    )
                case .magnet(let text):
                    _ = engine.addMagnet(
                        text,
                        destination: nil,
                        startPaused: paused,
                        sequential: sequential
                    )
                }
            }
        }
    }
}


/// Dispatches the menu/shortcut notifications received by `RootView`.
/// The closures do the actual work; this type only maps notifications to
/// actions, which makes the routing testable without a hosted SwiftUI view.
struct RootEventHandlerActions {
    var onAddFile: () -> Void = {}
    var onAddMagnet: () -> Void = {}
    var onPasteMagnet: () -> Void = {}
    var onPauseResume: () -> Void = {}
    var onRemove: () -> Void = {}
    var onReveal: () -> Void = {}
    var onCopyMagnet: () -> Void = {}
    var onFind: () -> Void = {}
    var onToggleInspector: () -> Void = {}
    var onSettings: () -> Void = {}
    var onDiagnostics: () -> Void = {}
    var onFilter: (String) -> Void = { _ in }

    func handle(_ notification: Notification.Name, object: Any? = nil) {
        switch notification {
        case .vertexAddFile: onAddFile()
        case .vertexAddMagnet: onAddMagnet()
        case .vertexPasteMagnet: onPasteMagnet()
        case .vertexPauseResume: onPauseResume()
        case .vertexRemove: onRemove()
        case .vertexReveal: onReveal()
        case .vertexCopyMagnet: onCopyMagnet()
        case .vertexFind: onFind()
        case .vertexToggleInspector: onToggleInspector()
        case .vertexSettings: onSettings()
        case .vertexDiagnostics: onDiagnostics()
        case .vertexFilter:
            guard let raw = object as? String else { return }
            onFilter(raw)
        default:
            return
        }
    }
}

private struct RootEventHandlers: ViewModifier {
    let actions: RootEventHandlerActions

    func body(content: Content) -> some View {
        content.onReceive(
            Publishers.MergeMany(
                AppCommand.notifications.map {
                    NotificationCenter.default.publisher(for: $0)
                }
            )
        ) { note in
            actions.handle(note.name, object: note.object)
        }
    }
}
