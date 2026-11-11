import SwiftUI

struct HeaderBar: View {
    @ObservedObject var engine: TorrentEngine
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    let onAdd: () -> Void
    let onSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 12) {
            LogoMark(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "Vertex")
                        .font(Typography.modalTitleText)
                        .foregroundStyle(palette.text)
                    Text(verbatim: "v\(AppInfo.version)")
                        .font(Typography.captionTinyMonoText)
                        .foregroundStyle(palette.tertiary)
                }
                Text(verbatim: "TORRENT CLIENT")
                    .font(Typography.badgeText)
                    .tracking(1.6)
                    .foregroundStyle(palette.tertiary)
            }

            Spacer(minLength: 20)

            searchField(palette)

            Button(action: onAdd) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(Typography.microSemiboldText)
                    Text("Aggiungi")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .help("Aggiungi un torrent")
            .disabled(!engine.isReady || engine.isRestartingSession)

            IconButton(icon: "gearshape", help: "Impostazioni", size: 30, action: onSettings)
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 62)
    }

    private func searchField(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(Typography.smallMediumText)
                .foregroundStyle(searchFocused.wrappedValue ? Theme.mint : palette.tertiary)

            TextField("Cerca torrent…", text: $search)
                .textFieldStyle(.plain)
                .font(Typography.bodyLargeRegularText)
                .foregroundStyle(palette.text)
                .focused(searchFocused)

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.captionText)
                        .foregroundStyle(palette.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: 236)
        .frame(minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(searchFocused.wrappedValue ? Theme.mint.opacity(0.4) : palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: searchFocused.wrappedValue)
    }
}

struct FilterBar: View {
    @Binding var filter: TorrentFilter
    @Binding var sort: TorrentSort
    @Binding var sortAscending: Bool
    let counts: [TorrentFilter: Int]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 6) {
            ForEach(TorrentFilter.allCases) { option in
                FilterChip(
                    title: option.label,
                    count: counts[option, default: 0],
                    selected: filter == option
                ) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                        filter = option
                    }
                }
            }

            Spacer()

            Menu {
                ForEach(TorrentSort.allCases) { option in
                    Button {
                        if sort == option {
                            sortAscending.toggle()
                        } else {
                            sort = option
                            // A→Z for names, "most important first" for the rest.
                            sortAscending = option.defaultAscending
                        }
                    } label: {
                        Label(option.label, systemImage: sort == option ? "checkmark" : option.icon)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(Typography.microSemiboldText)
                    Text(sort.label)
                        .font(Typography.bodyMediumText)
                    Image(systemName: "chevron.down")
                        .font(Typography.badgeText)
                        .opacity(0.55)
                }
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: 27)
                .background(Capsule().fill(palette.input))
                .overlay(Capsule().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                    sortAscending.toggle()
                }
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .font(Typography.microSemiboldText)
                    .foregroundStyle(palette.secondary)
                    .padding(.vertical, 4)
                    .frame(minWidth: 34, minHeight: 27)
                    .background(Capsule().fill(palette.input))
                    .overlay(Capsule().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Inverti ordine")
            .accessibilityLabel(Text(L("Inverti ordine")))
        }
        .padding(.horizontal, 18)
        .padding(.top, 3)
        .padding(.bottom, 11)
    }
}
