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

    static let warmGradient = LinearGradient(
        colors: [violet, blue],
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

    var secondary: Color {
        isDark ? Color.white.opacity(0.52) : Color(hex: 0x11131A).opacity(0.56)
    }

    var tertiary: Color {
        isDark ? Color.white.opacity(0.34) : Color(hex: 0x11131A).opacity(0.38)
    }

    var card: Color {
        isDark ? Color.white.opacity(0.035) : Color.white.opacity(0.72)
    }

    var cardHover: Color {
        isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.95)
    }

    var stroke: Color {
        isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
    }

    var strokeStrong: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    var panel: Color {
        isDark ? Color(hex: 0x10131A).opacity(0.82) : Color.white.opacity(0.78)
    }

    var input: Color {
        isDark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    var background: Color {
        isDark ? Color(hex: 0x08090D) : Color(hex: 0xF3F5FA)
    }

    var shadow: Color {
        isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.09)
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
                colors: [Theme.mint.opacity(scheme == .dark ? 0.15 : 0.2), .clear],
                center: .init(x: 0.12, y: 0.02),
                startRadius: 0,
                endRadius: 820
            )

            RadialGradient(
                colors: [Theme.violet.opacity(scheme == .dark ? 0.16 : 0.14), .clear],
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

struct DotGrid: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
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
            context.fill(path, with: .color(color))
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

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.minSize = NSSize(width: 980, height: 760)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
