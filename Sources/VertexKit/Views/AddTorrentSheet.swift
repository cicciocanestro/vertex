import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AddTorrentMode: String, CaseIterable, Identifiable {
    case magnet = "Magnet"
    case file = "File"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .magnet: return "link"
        case .file: return "doc"
        }
    }
}

struct AddTorrentSheet: View {
    @ObservedObject var engine: TorrentEngine

    @Environment(\.colorScheme) private var scheme
    // Per-torrent choices: initialised from the saved defaults, never written back to them.
    @StateObject private var downloadPath = UIState(Preferences.downloadPath)
    @StateObject private var startPaused = UIState(UserDefaults.standard.bool(forKey: PrefKey.startPaused))
    @StateObject private var sequential = UIState(UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault))

    @StateObject private var mode = UIState<AddTorrentMode>(.magnet)
    @StateObject private var magnet = UIState("")
    @StateObject private var fileURL = UIState<URL?>(nil)
    @StateObject private var errorMessage = UIState<String?>(nil)
    @StateObject private var dropTargeted = UIState(false)

    @FocusState private var magnetFocused: Bool

    let onClose: () -> Void

    init(engine: TorrentEngine, initialMode: AddTorrentMode, onClose: @escaping () -> Void) {
        _engine = ObservedObject(wrappedValue: engine)
        _mode = StateObject(wrappedValue: UIState(initialMode))
        self.onClose = onClose
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 15) {
            header(palette)
            modePicker(palette)
            inputContent(palette)
            destinationRow(palette)
            toggles(palette)

            if let message = errorMessage.value {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text(message)
                        .font(.system(size: 10.5))
                        .lineLimit(2)
                }
                .foregroundStyle(Theme.coral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            footer(palette)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(width: 540)
        .background(AmbientBackground(ignoresSafeArea: false))
        .overlay {
            if dropTargeted.value {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.mint.opacity(0.06))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            Theme.mint.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                        )
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(Theme.mint)
                        Text("Rilascia il file .torrent")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.text)
                    }
                }
                .padding(6)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onDrop(of: [.fileURL, .text], isTargeted: $dropTargeted.value) { providers in
            handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted.value)
        .onAppear {
            if mode.value == .magnet {
                DispatchQueue.main.async {
                    magnetFocused = true
                }
            }
        }
    }

    private func header(_ palette: Palette) -> some View {
        HStack(spacing: 12) {
            LogoMark(size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("Aggiungi torrent")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text("Un link magnet o un file .torrent")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }

            Spacer()

            IconButton(icon: "xmark", help: "Chiudi", size: 26) {
                onClose()
            }
        }
    }

    private func modePicker(_ palette: Palette) -> some View {
        HStack(spacing: 3) {
            ForEach(AddTorrentMode.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        mode.value = option
                        errorMessage.value = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.icon)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(option.rawValue)
                    }
                    .font(.system(size: 11, weight: mode.value == option ? .semibold : .medium))
                    .foregroundStyle(mode.value == option ? palette.text : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(mode.value == option ? palette.cardHover : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.input)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                        .allowsHitTesting(false)
                )
        )
    }

    @ViewBuilder
    private func inputContent(_ palette: Palette) -> some View {
        switch mode.value {
        case .magnet:
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $magnet.value)
                        .focused($magnetFocused)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .scrollContentBackground(.hidden)
                        .padding(.leading, 8)
                        .padding(.vertical, 8)
                        .padding(.trailing, 26)
                        .frame(height: 88)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(palette.input)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(
                                    magnet.value.isEmpty ? palette.stroke : Theme.mint.opacity(0.3),
                                    lineWidth: 1
                                )
                                .allowsHitTesting(false)
                        )

                    if magnet.value.isEmpty {
                        Text("magnet:?xt=urn:btih:…")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    if !magnet.value.isEmpty {
                        Button {
                            magnet.value = ""
                            errorMessage.value = nil
                            magnetFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.tertiary)
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Svuota il campo")
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            magnet.value = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                            errorMessage.value = nil
                        }
                    } label: {
                        Label("Incolla", systemImage: "doc.on.clipboard")
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(Capsule().fill(palette.input))
                            .overlay(Capsule().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondary)

                    Text("Oppure trascina qui un file .torrent")
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.tertiary)

                    Spacer()
                }
            }
            .frame(height: 118, alignment: .top)

        case .file:
            fileDropZone(palette)
                .frame(height: 118)
        }
    }

    private func fileDropZone(_ palette: Palette) -> some View {
        VStack(spacing: 8) {
            if let fileURL = fileURL.value {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.mint)

                Text(fileURL.lastPathComponent)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 24)

                HStack(spacing: 10) {
                    Button("Cambia file…") {
                        chooseFile()
                    }
                    .buttonStyle(SmallButtonStyle())

                    if let size = fileSize(fileURL) {
                        Text(Fmt.bytes(size))
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(palette.tertiary)
                    }
                }
            } else {
                Image(systemName: dropTargeted.value ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(dropTargeted.value ? Theme.mint : palette.secondary)

                Text("Trascina qui un file .torrent")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.secondary)

                Button("Scegli file…") {
                    chooseFile()
                }
                .buttonStyle(SmallButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dropTargeted.value ? Theme.mint.opacity(0.07) : palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted.value ? Theme.mint.opacity(0.6) : palette.strokeStrong,
                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                )
                .allowsHitTesting(false)
        )
    }

    private func destinationRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.mint)

            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Cartella per questo torrent")
                Text(downloadPath.value)
                    .font(.system(size: 10.3, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(downloadPath.value)
            }

            Spacer(minLength: 8)

            Button("Cartella…") {
                chooseDestination()
            }
            .buttonStyle(SmallButtonStyle())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func toggles(_ palette: Palette) -> some View {
        HStack(spacing: 22) {
            Toggle("Avvia in pausa", isOn: $startPaused.value)
            Toggle("Download sequenziale", isOn: $sequential.value)
            Spacer()
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(palette.secondary)
        .tint(Theme.teal)
    }

    private func footer(_ palette: Palette) -> some View {
        HStack(spacing: 9) {
            Spacer()

            Button("Annulla") {
                onClose()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button("Aggiungi") {
                add()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdd)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 2)
    }

    private var canAdd: Bool {
        switch mode.value {
        case .magnet:
            let value = magnet.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.lowercased().hasPrefix("magnet:")
        case .file:
            return fileURL.value != nil
        }
    }

    private func add() {
        errorMessage.value = nil
        let failure: String?
        switch mode.value {
        case .magnet:
            failure = engine.addMagnet(
                magnet.value,
                destination: downloadPath.value,
                startPaused: startPaused.value,
                sequential: sequential.value
            )
        case .file:
            guard let url = fileURL.value else { return }
            failure = engine.addTorrentFile(
                url,
                destination: downloadPath.value,
                startPaused: startPaused.value,
                sequential: sequential.value
            )
        }

        if let failure {
            withAnimation(.easeOut(duration: 0.15)) {
                errorMessage.value = failure
            }
        } else {
            onClose()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    DispatchQueue.main.async {
                        fileURL.value = url
                        mode.value = .file
                        errorMessage.value = nil
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String,
                          text.lowercased().hasPrefix("magnet:") else { return }
                    DispatchQueue.main.async {
                        magnet.value = text
                        mode.value = .magnet
                        errorMessage.value = nil
                    }
                }
            }
        }

        return handled
    }

    private func chooseFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = .modalPanel
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Scegli")
        if let type = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK, let url = panel.url {
            fileURL.value = url
            errorMessage.value = nil
        }
    }

    private func chooseDestination() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = .modalPanel
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Scegli")
        panel.directoryURL = URL(fileURLWithPath: downloadPath.value)
        if panel.runModal() == .OK, let url = panel.url {
            downloadPath.value = url.path
        }
    }

    private func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return Int64(size)
    }
}

struct SmallButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = Palette(scheme: scheme)
        configuration.label
            .font(.system(size: 9.8, weight: .medium))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(palette.cardHover))
            .overlay(Capsule().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
