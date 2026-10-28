import AppKit
import SwiftUI

struct NetworkDiagnosticsView: View {
    @ObservedObject var engine: TorrentEngine
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var tester = PortReachabilityTester()
    /// Resolved once per presentation instead of re-running `getifaddrs` on
    /// every render.
    @StateObject private var localIP = UIState(LocalNetwork.primaryIPv4Address() ?? "—")
    @AppStorage(PrefKey.dhtEnabled) private var dhtEnabled = PrefDefault.dhtEnabled

    /// Port to probe from outside: the NAT-mapped external TCP port if any, otherwise the listen port.
    private var testPort: Int {
        let mapping = engine.stats.portmap.tcp
        return mapping.mapped && mapping.externalPort > 0
            ? mapping.externalPort
            : engine.stats.effectivePort
    }

    var body: some View {
        let palette = Palette(scheme: scheme)

        VStack(spacing: 0) {
            ModalHeader(
                icon: "network",
                title: "Diagnostica rete",
                subtitle: "Porta, mapping UPnP/NAT-PMP e raggiungibilità esterna",
                iconSize: 38,
                onClose: onClose
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    statusGrid(palette)
                    mappingCard(palette)
                    reachabilityCard(palette)
                    instructions(palette)
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            ModalFooterBar(palette: palette) {
                Button("Impostazioni rete") {
                    onOpenSettings()
                }
                .buttonStyle(SecondaryButtonStyle())
            } trailing: {
                Button("Chiudi") {
                    onClose()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(width: 620, height: 650)
        .background(AmbientBackground(ignoresSafeArea: false))
        .onDisappear { tester.cancel() }
        .onChange(of: testPort) { _, _ in tester.reset() }
    }

    private func statusGrid(_ palette: Palette) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statusCard(
                title: "Stato",
                value: L(engine.stats.isListening ? "In ascolto" : "Non in ascolto"),
                detail: L(engine.stats.isListening ? "socket TCP/UDP attivo" : "in attesa del socket"),
                color: engine.stats.isListening ? Theme.green : Theme.coral,
                palette: palette
            )

            statusCard(
                title: "Porta",
                value: engine.stats.effectivePort > 0 ? "\(engine.stats.effectivePort)" : "—",
                detail: engine.stats.actualPort > 0 && engine.stats.actualPort != engine.stats.port
                    ? LF("configurata %ld", engine.stats.port)
                    : L("TCP e UDP"),
                palette: palette
            )

            statusCard(
                title: "IP locale",
                value: localIP.value,
                detail: L("interfaccia di rete principale"),
                palette: palette
            )

            statusCard(
                title: "Nodi DHT",
                value: dhtEnabled ? "\(engine.stats.dhtNodes)" : "—",
                detail: L(!dhtEnabled ? "DHT disattivato"
                    : (engine.stats.dhtNodes > 0 ? "rete DHT attiva" : "in connessione")),
                color: dhtEnabled
                    ? (engine.stats.dhtNodes > 0 ? Theme.blue : Theme.amber)
                    : palette.tertiary,
                palette: palette
            )
        }
    }

    private func statusCard(
        title: String,
        value: String,
        detail: String,
        color: Color? = nil,
        palette: Palette
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: title)
            HStack(spacing: 6) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .vertexCard(palette, radius: 11)
    }

    private func mappingCard(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Mapping UPnP / NAT-PMP")

            VStack(spacing: 0) {
                mappingRow("TCP", info: engine.stats.portmap.tcp, palette: palette)
                Hairline(palette: palette)
                mappingRow("UDP", info: engine.stats.portmap.udp, palette: palette)

                if !engine.stats.portmap.error.isEmpty {
                    Hairline(palette: palette)
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.coral)
                        Text(engine.stats.portmap.error)
                            .font(.system(size: 9.8))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .vertexCard(palette, radius: 12)

            if !engine.stats.portmap.tcp.mapped && !engine.stats.portmap.udp.mapped
                && !engine.stats.portmap.hasError {
                Text("Nessuna mappatura rilevata. Il router potrebbe avere UPnP/NAT-PMP disabilitato.")
                    .font(.system(size: 9.8))
                    .foregroundStyle(palette.tertiary)
            }
        }
    }

    private func mappingRow(_ label: String, info: PortMapInfo, palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(info.mapped ? Theme.green : (info.hasError ? Theme.coral : Theme.amber))
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.text)

                Spacer()

                if info.mapped {
                    Text(LF("porta esterna %ld", info.externalPort))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.secondary)
                    if !info.transport.isEmpty {
                        Text(info.transport)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.green.opacity(0.12)))
                    }
                } else {
                    Text("non mappata")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.tertiary)
                }
            }

            if info.hasError {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.coral)
                    Text(info.error)
                        .font(.system(size: 9.8))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 8)
    }

    private func reachabilityCard(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Raggiungibilità esterna")

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    testStateIcon
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.top, 1)

                    Text(testStateText)
                        .font(.system(size: 10.8))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let publicIP = tester.publicIP {
                    HStack(spacing: 8) {
                        Text("\(publicIP):\(testPort)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(publicIP):\(testPort)", forType: .string)
                            engine.showToast(L("Indirizzo copiato"), kind: .info)
                        } label: {
                            Label("Copia", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(SmallButtonStyle())
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.input)
                    )
                }

                HStack(spacing: 8) {
                    Button(testButtonTitle) {
                        tester.start(port: testPort)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(testPort <= 0 || isTesting)

                    if case .idle = tester.state {
                        Text("Test TCP tramite check-host.net")
                            .font(.system(size: 9.2))
                            .foregroundStyle(palette.tertiary)
                    }
                }
            }
            .padding(12)
            .vertexCard(palette, radius: 12)
        }
    }

    private var isTesting: Bool {
        if case .running = tester.state { return true }
        return false
    }

    private var testButtonTitle: String {
        switch tester.state {
        case .idle, .running:
            return L("Testa porta")
        default:
            return L("Riprova")
        }
    }

    private var testStateText: String {
        switch tester.state {
        case .idle:
            return L("Verifica se la porta TCP è raggiungibile da Internet. L’IP pubblico viene inviato a check-host.net solo quando avvii il test.")
        case .running:
            return L("Test in corso: attendo la risposta dei nodi esterni…")
        case .open(let open, let total):
            return LF("Porta raggiungibile da %ld nodi esterni su %ld. Il NAT/router inoltra correttamente il traffico.", open, total)
        case .closed(let total):
            return LF("Nessuno dei %ld nodi esterni ha raggiunto la porta. Controlla port forwarding, UPnP e firewall del router.", total)
        case .failed(let message):
            return message
        }
    }

    private var testStateIcon: some View {
        Group {
            switch tester.state {
            case .idle:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Theme.amber)
            case .running:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.blue)
            case .open:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            case .closed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.coral)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private func instructions(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Se la porta risulta chiusa")

            instruction(LF("Abilita UPnP/NAT-PMP nel router, oppure inoltra TCP e UDP %ld verso %@.", engine.stats.effectivePort, localIP.value), palette)
            instruction(L("Verifica che l’IP WAN del router coincida con l’IP pubblico: se è diverso potresti essere dietro CGNAT."), palette)
            instruction(L("Il test copre solo il TCP; il traffico UDP/uTP non è verificato."), palette)
        }
    }

    private func instruction(_ text: String, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(palette.tertiary)
                .frame(width: 3.5, height: 3.5)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 9.8))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}
