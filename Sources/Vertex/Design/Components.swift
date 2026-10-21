import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let phase: TorrentPhase
    var size: CGFloat = 46

    @Environment(\.colorScheme) private var scheme
    @StateObject private var spin = UIState(false)

    private var lineWidth: CGFloat { max(3, size * 0.085) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(scheme == .dark ? 0.09 : 0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.012, min(progress, 1)))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.45), value: progress)

            icon
        }
        .frame(width: size, height: size)
    }

    private var ringGradient: LinearGradient {
        switch phase {
        case .downloading:
            return LinearGradient(colors: [Theme.mint, Theme.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .metadata:
            return LinearGradient(colors: [Theme.amber, Theme.coral], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .checking:
            return LinearGradient(colors: [Theme.blue, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .seeding:
            return LinearGradient(colors: [Theme.violet, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .completed:
            return LinearGradient(colors: [Theme.green, Theme.mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paused:
            return LinearGradient(colors: [Color.primary.opacity(0.28), Color.primary.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var iconColor: Color {
        switch phase {
        case .paused: return Color.primary.opacity(0.45)
        case .metadata: return Theme.amber
        case .checking: return Theme.blue
        case .seeding: return Theme.violet
        case .completed: return Theme.green
        case .downloading: return Color.primary.opacity(0.82)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundStyle(iconColor)
        case .seeding:
            Image(systemName: "arrow.up")
                .font(.system(size: size * 0.27, weight: .bold))
                .foregroundStyle(iconColor)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.27, weight: .bold))
                .foregroundStyle(iconColor)
        case .metadata:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.24, weight: .semibold))
                .foregroundStyle(iconColor)
        case .checking:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: size * 0.25, weight: .semibold))
                .foregroundStyle(iconColor)
                .rotationEffect(.degrees(spin.value ? 360 : 0))
                .animation(.linear(duration: 1.8).repeatForever(autoreverses: false), value: spin.value)
                .onAppear { spin.value = true }
        case .downloading:
            Text(Fmt.percent(progress))
                .font(.system(size: size * 0.215, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(iconColor)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color(hex: 0x071016).opacity(isEnabled ? 0.92 : 0.45))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accentGradient)
                    .opacity(isEnabled ? 1 : 0.45)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Theme.violet.opacity(configuration.isPressed ? 0.08 : 0.26), radius: 12, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = Palette(scheme: scheme)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(palette.text.opacity(configuration.isPressed ? 0.6 : 0.84))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let icon: String
    var help: String = ""
    var tint: Color?
    var size: CGFloat = 27
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = UIState(false)

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint ?? Color.primary.opacity(hover.value ? 0.88 : 0.5))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(hover.value ? Color.primary.opacity(scheme == .dark ? 0.09 : 0.06) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
        .help(help)
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = UIState(false)

    var body: some View {
        let palette = Palette(scheme: scheme)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(selected ? Theme.mint.opacity(0.2) : Color.primary.opacity(0.07))
                        )
                }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? palette.text : palette.secondary)
            .padding(.horizontal, 12)
            .frame(height: 27)
            .background(
                Capsule()
                    .fill(selected
                          ? Theme.mint.opacity(scheme == .dark ? 0.13 : 0.18)
                          : (hover.value ? palette.input : .clear))
            )
            .overlay(
                Capsule()
                    .stroke(
                        selected
                            ? Theme.mint.opacity(0.38)
                            : (hover.value ? palette.stroke : .clear),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover.value = $0 }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let peak = max(values.max() ?? 0, 1)
            var path = Path()

            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let normalized = CGFloat(max(0, value) / peak)
                let y = size.height - 1 - normalized * (size.height - 3)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var area = path
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.24), color.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                path,
                with: .color(color.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }
}

struct PulsingDot: View {
    let color: Color
    @StateObject private var pulse = UIState(false)

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 10, height: 10)
                .scaleEffect(pulse.value ? 1.7 : 0.6)
                .opacity(pulse.value ? 0 : 1)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) {
                pulse.value = true
            }
        }
    }
}

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var accent: Color {
        switch toast.kind {
        case .success: return Theme.green
        case .error: return Theme.coral
        case .info: return Theme.blue
        }
    }

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark"
        case .error: return "exclamationmark"
        case .info: return "info"
        }
    }

    var body: some View {
        let palette = Palette(scheme: scheme)
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.text)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.tertiary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.strokeStrong, lineWidth: 1)
        )
        .shadow(color: palette.shadow, radius: 20, x: 0, y: 8)
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Palette(scheme: scheme).tertiary)
    }
}

struct SpeedText: View {
    let value: Int64
    let upload: Bool
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let color = value > 0 ? (upload ? Theme.violet : Theme.mint) : palette.tertiary
        HStack(spacing: 3) {
            Image(systemName: upload ? "arrow.up" : "arrow.down")
                .font(.system(size: compact ? 7.5 : 8.5, weight: .bold))
            Text(Fmt.rate(value))
                .font(.system(size: compact ? 9.5 : 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }
}
