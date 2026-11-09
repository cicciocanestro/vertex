import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    static let mint = Color(hex: 0x5EEAD4)
    static let teal = Color(hex: 0x2DD4BF)
    static let blue = Color(hex: 0x5B9DFF)
    static let violet = Color(hex: 0x8B7CFF)
    static let amber = Color(hex: 0xF5B95C)
    static let coral = Color(hex: 0xFF7A8A)
    static let green = Color(hex: 0x67E8A5)

    static let accentGradient = LinearGradient(
        colors: [mint, Color(hex: 0x7C8CFF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct Palette {
    let scheme: ColorScheme
    var isDark: Bool { scheme == .dark }

    var text: Color {
        isDark ? Color.white.opacity(0.93) : Color(hex: 0x11131A)
    }

    // Secondary and tertiary are used for informative text (subtitles, stat
    // labels, status bar), not only for decoration: the values below keep both
    // themes above ~4.5:1 on the card backgrounds, which the previous 0.34 /
    // 0.38 alpha values did not.
    var secondary: Color {
        isDark ? Color.white.opacity(0.60) : Color(hex: 0x11131A).opacity(0.68)
    }

    var tertiary: Color {
        isDark ? Color.white.opacity(0.46) : Color(hex: 0x11131A).opacity(0.58)
    }

    // Cards are slightly more opaque and their border more visible, so the
    // light theme does not look like white cards on a white background.
    var card: Color {
        isDark ? Color.white.opacity(0.045) : Color.white.opacity(0.85)
    }

    var cardHover: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.98)
    }

    var stroke: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.12)
    }

    var strokeStrong: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.20)
    }

    var panel: Color {
        isDark ? Color(hex: 0x10131A).opacity(0.82) : Color.white.opacity(0.86)
    }

    var input: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.055)
    }

    var background: Color {
        isDark ? Color(hex: 0x08090D) : Color(hex: 0xF3F5FA)
    }

    var shadow: Color {
        isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.09)
    }

    // MARK: - Accent colours for text and icons
    //
    // The saturated accents above are tuned for the dark background: on the
    // light card they fall below 3:1 (mint 1.44:1, green 1.50:1, amber 1.71:1,
    // coral 2.43:1, blue 2.65:1, violet 3.18:1), which is unreadable at the
    // 9–11 pt sizes the views use. These twins keep the hue and reach at least
    // 5.2:1 on the light card. Use them for `foregroundStyle` and keep
    // `Theme.*` for fills, rings, gradients and glows.

    var mintText: Color { isDark ? Theme.mint : Color(hex: 0x0E7490) }
    var violetText: Color { isDark ? Theme.violet : Color(hex: 0x5B4BD6) }
    var coralText: Color { isDark ? Theme.coral : Color(hex: 0xC02A45) }
    var amberText: Color { isDark ? Theme.amber : Color(hex: 0x9A5B00) }
    var greenText: Color { isDark ? Theme.green : Color(hex: 0x0F7A4A) }
    var blueText: Color { isDark ? Theme.blue : Color(hex: 0x1C62C8) }

    /// Text colour for a torrent state pill.
    func phaseText(_ phase: TorrentPhase) -> Color {
        switch phase {
        case .downloading: return mintText
        case .metadata: return amberText
        case .checking: return blueText
        case .seeding: return violetText
        case .completed: return greenText
        case .paused: return Color.primary.opacity(0.5)
        }
    }

    /// Saturated accent for fills (progress track, dots, glows). Text must use
    /// `phaseText(_:)`: these values are too bright on the light card.
    func phaseAccent(_ phase: TorrentPhase) -> Color {
        switch phase {
        case .downloading: return Theme.mint
        case .metadata: return Theme.amber
        case .checking: return Theme.blue
        case .seeding: return Theme.violet
        case .completed: return Theme.green
        case .paused: return Color.primary.opacity(0.28)
        }
    }
}

struct AmbientBackground: View {
    var ignoresSafeArea: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        ZStack {
            palette.background

            RadialGradient(
                colors: [Theme.mint.opacity(scheme == .dark ? 0.15 : 0.12), .clear],
                center: .init(x: 0.12, y: 0.02),
                startRadius: 0,
                endRadius: 820
            )

            RadialGradient(
                colors: [Theme.violet.opacity(scheme == .dark ? 0.16 : 0.09), .clear],
                center: .init(x: 0.92, y: 0.98),
                startRadius: 0,
                endRadius: 900
            )

            DotGrid(
                color: scheme == .dark
                    ? Color.white.opacity(0.030)
                    : Color.black.opacity(0.035)
            )
        }
        .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
    }
}

private final class DotGridCache: ObservableObject {
    var path = Path()
    var size: CGSize = .zero
}

struct DotGrid: View {
    let color: Color
    @StateObject private var cache = DotGridCache()

    var body: some View {
        Canvas { context, size in
            if cache.size != size {
                let step: CGFloat = 28
                var path = Path()
                var x: CGFloat = step / 2
                while x < size.width {
                    var y: CGFloat = step / 2
                    while y < size.height {
                        path.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                        y += step
                    }
                    x += step
                }
                cache.path = path
                cache.size = size
            }
            context.fill(cache.path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

struct VMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct LogoMark: View {
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(Theme.accentGradient)
            .overlay(
                VMark()
                    .stroke(
                        Color(hex: 0x061014).opacity(0.88),
                        style: StrokeStyle(
                            lineWidth: size * 0.105,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(size * 0.29)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
            )
            .shadow(color: Theme.mint.opacity(0.28), radius: size * 0.4, x: 0, y: size * 0.12)
            .frame(width: size, height: size)
    }
}

/// Minimum size of the main window: the SwiftUI scene and the AppKit window
/// both read it, so the two cannot drift apart.
package enum WindowMetrics {
    package static let minimumWidth: CGFloat = 980
    package static let minimumHeight: CGFloat = 760
}

private final class WindowConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Apply the chrome as soon as the view is in a window instead of on
        // the next run loop: the first frame already has the final look.
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = NSSize(
            width: WindowMetrics.minimumWidth,
            height: WindowMetrics.minimumHeight
        )
    }
}

package struct WindowConfigurator: NSViewRepresentable {
    package init() {}

    package func makeNSView(context: Context) -> NSView {
        WindowConfiguratorView()
    }

    package func updateNSView(_ nsView: NSView, context: Context) {}
}
