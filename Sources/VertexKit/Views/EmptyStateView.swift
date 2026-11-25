import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void
    let onPasteMagnet: () -> Void
    let onOpenSettings: () -> Void

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
                Text(L("Nessun torrent"))
                    .font(Typography.heroText)
                    .foregroundStyle(palette.text)

                Text(L("Aggiungi un file .torrent o incolla un link magnet per iniziare."))
                    .font(Typography.bodyLargeRegularText)
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(alignment: .top, spacing: 8) {
                onboardingStep(
                    "1",
                    icon: "plus.circle",
                    title: L("Aggiungi"),
                    detail: L("File .torrent o link magnet"),
                    palette: palette
                )
                onboardingStep(
                    "2",
                    icon: "folder",
                    title: L("Cartella"),
                    detail: L("Scegli dove salvare i file"),
                    palette: palette
                )
                onboardingStep(
                    "3",
                    icon: "shield.lefthalf.filled",
                    title: L("Proxy"),
                    detail: L("Facoltativo, per la privacy"),
                    palette: palette
                )
            }

            HStack(spacing: 9) {
                Button(L("Aggiungi torrent"), action: onAdd)
                    .buttonStyle(PrimaryButtonStyle())

                Button(action: onPasteMagnet) {
                    Label(L("Incolla magnet"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 7) {
                Image(systemName: "arrow.down.doc")
                    .font(Typography.captionMediumText)
                Text(L("Trascina qui i file .torrent"))
                    .font(Typography.smallMediumText)
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
                    .allowsHitTesting(false)
            )
            .padding(.top, 2)

            Button(action: onOpenSettings) {
                Label(L("Apri impostazioni"), systemImage: "gearshape")
                    .font(Typography.smallMediumText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 22)
    }

    private func onboardingStep(
        _ number: String,
        icon: String,
        title: String,
        detail: String,
        palette: Palette
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.mint.opacity(0.16))
                    .frame(width: 20, height: 20)
                Text(verbatim: number)
                    .font(Typography.captionTinySemiboldText)
                    .foregroundStyle(palette.mintText)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(Typography.captionTinySemiboldText)
                        .foregroundStyle(palette.tertiary)
                    Text(title)
                        .font(Typography.smallSemiboldText)
                        .foregroundStyle(palette.text)
                }
                Text(detail)
                    .font(Typography.microText)
                    .foregroundStyle(palette.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 176, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
        )
    }
}

/// Persistent failure state for the embedded engine. The retry button asks the
/// engine to create the session again off the main actor.
struct EngineUnavailableView: View {
    let message: String
    let onRetry: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.iconHero)
                .foregroundStyle(Theme.coral)

            Text(L("Motore BitTorrent non disponibile"))
                .font(Typography.heroText)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Typography.bodyLargeText)
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            Button(L("Riprova")) {
                onRetry()
            }
            .buttonStyle(PrimaryButtonStyle())
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
                .font(Typography.bodyLargeText)
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

            Text(L("Nessun risultato"))
                .font(Typography.sectionTitleText)
                .foregroundStyle(palette.text)

            Text(
                query.isEmpty
                    ? L("Nessun torrent in questo filtro.")
                    : LF("Nessun torrent corrisponde a “%@”.", query)
            )
            .font(Typography.bodyLargeText)
            .foregroundStyle(palette.secondary)

            Button(L("Azzera filtri"), action: onReset)
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
                    .font(Typography.iconDrop)
                    .foregroundStyle(Theme.mint)

                Text(L("Rilascia per aggiungere"))
                    .font(Typography.modalTitleText)

                Text(L(".torrent o link magnet"))
                    .font(Typography.bodyText)
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
