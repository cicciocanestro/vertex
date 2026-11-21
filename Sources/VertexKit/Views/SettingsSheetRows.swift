import SwiftUI

extension SettingsSheet {
    func numericRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<Int>,
        suffix: String,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.smallRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 62, maxWidth: 84)
                    .accessibilityLabel(Text(L(title)))

                Text(suffix)
                    .font(Typography.microMediumText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .padding(.vertical, 8)
    }

    func decimalRow(
        icon: String,
        title: String,
        subtitle: String,
        value: Binding<Double>,
        suffix: String,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Typography.smallRoundedMediumText)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .frame(minWidth: 52, maxWidth: 72)
                    .accessibilityLabel(Text(L(title)))

                Text(suffix)
                    .font(Typography.microMediumText)
                    .foregroundStyle(palette.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .padding(.vertical, 8)
    }

    func bindingRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Interfaccia di rete"))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Il traffico esce solo da questo indirizzo"))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Menu {
                Button {
                    bindAddress = ""
                } label: {
                    if bindAddress.isEmpty {
                        Label(L("Automatica"), systemImage: "checkmark")
                    } else {
                        Text(L("Automatica"))
                    }
                }

                if !interfaces.value.isEmpty {
                    Divider()
                    ForEach(interfaces.value) { interface in
                        Button {
                            bindAddress = interface.address
                        } label: {
                            if bindAddress == interface.address {
                                Label(interface.label, systemImage: "checkmark")
                            } else {
                                Text(interface.label)
                            }
                        }
                    }
                }
            } label: {
                bindingLabel(palette)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    func bindingLabel(_ palette: Palette) -> some View {
        HStack(spacing: 5) {
            Text(bindingText)
                .font(Typography.captionMediumRoundedText)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(Typography.badgeText)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
    }

    var bindingText: String {
        guard !bindAddress.isEmpty else { return L("Automatica") }
        if let match = interfaces.value.first(where: { $0.address == bindAddress }) {
            return match.label
        }
        return LF("%@ (non disponibile)", bindAddress)
    }

    func diagnosticsRow(_ palette: Palette) -> some View {
        Button {
            onOpenDiagnostics()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Diagnostica rete"))
                        .font(Typography.bodyLargeMediumText)
                        .foregroundStyle(palette.text)
                    Text(L("Porta effettiva, mapping e test esterno"))
                        .font(Typography.microText)
                        .foregroundStyle(palette.tertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(Typography.captionTinySemiboldText)
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func proxyHostRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Server e porta"))
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Host proxy SOCKS5 e porta"))
                    .font(Typography.captionTinyText)
                    .foregroundStyle(palette.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            TextField(Self.proxyHostPlaceholder, text: $proxyHost)
                .textFieldStyle(.plain)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 110, maxWidth: 150, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            Text(verbatim: ":")
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.tertiary)

            TextField(Self.proxyPortPlaceholder, value: $proxyPort, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .font(Typography.captionMonoText)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 55, maxWidth: 72, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )
        }
        .padding(.vertical, 7)
    }

    func proxyAuthRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Autenticazione"))
                    .font(Typography.bodyMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Facoltativa (RFC 1929)"))
                    .font(Typography.captionTinyText)
                    .foregroundStyle(palette.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            TextField(L("Utente"), text: $proxyUser)
                .textFieldStyle(.plain)
                .font(Typography.captionSmallText)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 85, maxWidth: 115, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )

            SecureField(L("Password"), text: $proxyPasswordValue.value)
                .textFieldStyle(.plain)
                .font(Typography.captionSmallText)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 85, maxWidth: 115, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.stroke, lineWidth: 1)
                )
        }
        .padding(.vertical, 7)
    }

    func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        palette: Palette
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L(title))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L(subtitle))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Toggle(L(title), isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.teal)
        }
        .padding(.vertical, 8)
    }

    func appearancePicker(_ palette: Palette) -> some View {
        SegmentedPicker(
            selection: appearance,
            palette: palette,
            height: 25,
            corner: 7,
            horizontalPadding: 3,
            verticalPadding: 3,
            font: Typography.captionMediumText
        ) { (option: AppearanceOption, _) in
            HStack(spacing: 5) {
                Image(systemName: option.icon)
                    .font(Typography.captionTinySemiboldText)
                Text(option.label)
            }
        }
    }

    private var densitySelection: Binding<ListDensity> {
        Binding(
            get: { ListDensity(rawValue: densityRaw) ?? .comfortable },
            set: { densityRaw = $0.rawValue }
        )
    }

    func densityPicker(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(L("Densità elenco"))
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(L("Righe più compatte mostrano più torrent"))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 8)

            SegmentedPicker(
                selection: densitySelection,
                palette: palette,
                height: 24,
                corner: 7,
                horizontalPadding: 2,
                verticalPadding: 2,
                font: Typography.captionMediumText
            ) { (option: ListDensity, _) in
                Text(option.label)
            }
            .frame(width: 168)
        }
        .padding(.vertical, 8)
    }

    func versionRow(_ palette: Palette) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(Typography.bodyMediumText)
                .foregroundStyle(palette.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Vertex")
                    .font(Typography.bodyLargeMediumText)
                    .foregroundStyle(palette.text)
                Text(LF("Versione %@ (build %@)", AppInfo.version, AppInfo.build))
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    func chooseFolder() {
        let panel = OpenPanelFactory.directory(startingAt: downloadPath)
        if panel.runModal() == .OK, let url = panel.url {
            downloadPath = url.path
            engine.applySettingsNow()
        }
    }
}
