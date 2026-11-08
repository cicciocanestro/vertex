import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void
    let onPasteMagnet: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.mint.opacity(0.085))
                    .frame(width: 158, height: 158)
                    .blur(radius: 40)
                LogoMark(size: 84)
            }

            VStack(spacing: 7) {
                Text("Nessun torrent")
                    .font(Typography.hero)
                    .foregroundStyle(palette.text)

                Text("Aggiungi un file .torrent o incolla un link magnet per iniziare.")
                    .font(Typography.bodyLargeRegular)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            HStack(spacing: 9) {
                Button("Aggiungi torrent", action: onAdd)
                    .buttonStyle(PrimaryButtonStyle())

                Button(action: onPasteMagnet) {
                    Label("Incolla magnet", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 7) {
                Image(systemName: "arrow.down.doc")
                    .font(Typography.captionMedium)
                Text("Trascina qui i file .torrent")
                    .font(Typography.smallMedium)
            }
            .foregroundStyle(palette.tertiary)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        palette.strokeStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 22)
    }
}

/// Shown until the first snapshot arrives, so a launch with existing torrents
/// does not flash the "no torrents" state.
struct LoadingStateView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 14) {
            LogoMark(size: 64)
            ProgressView()
                .controlSize(.small)
            Text(L("Caricamento torrent…"))
                .font(Typography.bodyLarge)
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 22)
    }
}

struct NoResultsView: View {
    let query: String
    let onReset: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(Typography.iconMedium)
                .foregroundStyle(palette.tertiary)

            Text("Nessun risultato")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.text)

            Text(query.isEmpty
                 ? L("Nessun torrent in questo filtro.")
                 : LF("Nessun torrent corrisponde a “%@”.", query))
                .font(Typography.bodyLarge)
                .foregroundStyle(palette.secondary)

            Button("Azzera filtri", action: onReset)
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 18)
    }
}

struct DropOverlay: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.4))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.mint)

                Text("Rilascia per aggiungere")
                    .font(Typography.modalTitle)

                Text(".torrent o link magnet")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 52)
            .padding(.vertical, 34)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        Theme.mint.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.4, dash: [7, 5])
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 30, y: 12)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
