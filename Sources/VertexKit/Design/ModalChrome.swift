import SwiftUI

/// Shared header for the custom modal overlays (settings and diagnostics).
struct ModalHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconSize: CGFloat = 38
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: iconSize * 0.27, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: iconSize, height: iconSize)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: iconSize * 0.42, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x061014).opacity(0.85))
                )
                .shadow(color: Theme.mint.opacity(0.2), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }

            Spacer()

            IconButton(icon: "xmark", help: "Chiudi", size: 26, action: onClose)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

/// Shared footer bar for the custom modal overlays.
struct ModalFooterBar<Leading: View, Trailing: View>: View {
    let palette: Palette
    let leading: Leading
    let trailing: Trailing

    init(
        palette: Palette,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.palette = palette
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 9) {
            leading
            Spacer()
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Hairline(palette: palette)
        }
    }
}

struct Hairline: View {
    let palette: Palette
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(palette.stroke)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
            .allowsHitTesting(false)
    }
}

private struct VertexCardModifier: ViewModifier {
    let palette: Palette
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func vertexCard(_ palette: Palette, radius: CGFloat = 12) -> some View {
        modifier(VertexCardModifier(palette: palette, radius: radius))
    }
}
