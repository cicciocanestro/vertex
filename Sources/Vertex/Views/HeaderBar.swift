import SwiftUI

struct HeaderBar: View {
    @ObservedObject var engine: TorrentEngine
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    let onAdd: () -> Void
    let onAddFile: () -> Void
    let onSettings: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 12) {
            LogoMark(size: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text("Vertex")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text("TORRENT CLIENT")
                    .font(.system(size: 7.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(palette.tertiary)
                Text("v\(AppInfo.version)")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 20)

            searchField(palette)

            Button(action: onAdd) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("Aggiungi")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .help("Aggiungi un torrent")

            IconButton(icon: "gearshape", help: "Impostazioni", size: 30, action: onSettings)
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .frame(height: 62)
    }

    private func searchField(_ palette: Palette) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(searchFocused.wrappedValue ? Theme.mint : palette.tertiary)

            TextField("Cerca torrent…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .focused(searchFocused)
                .onSubmit {}

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 236, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(searchFocused.wrappedValue ? Theme.mint.opacity(0.4) : palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.16), value: searchFocused.wrappedValue)
    }
}

struct FilterBar: View {
    @Binding var filter: TorrentFilter
    @Binding var sort: TorrentSort
    let torrents: [Torrent]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 6) {
            ForEach(TorrentFilter.allCases) { option in
                FilterChip(
                    title: option.label,
                    count: count(for: option),
                    selected: filter == option
                ) {
                    withAnimation(.snappy(duration: 0.18)) {
                        filter = option
                    }
                }
            }

            Spacer()

            Menu {
                ForEach(TorrentSort.allCases) { option in
                    Button {
                        sort = option
                    } label: {
                        Label(option.label, systemImage: sort == option ? "checkmark" : option.icon)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(sort.label)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.55)
                }
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(Capsule().fill(palette.input))
                .overlay(Capsule().stroke(palette.stroke, lineWidth: 1).allowsHitTesting(false))
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.top, 3)
        .padding(.bottom, 11)
    }

    private func count(for filter: TorrentFilter) -> Int {
        torrents.filter { filter.matches($0) }.count
    }
}
