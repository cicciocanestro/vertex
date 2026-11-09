import SwiftUI

/// Reusable segmented picker.
///
/// Three call sites — the inspector's tab bar, the settings appearance
/// selector and the add-torrent mode picker — rendered the same widget by
/// hand, so the padding, corner radius and font drifted apart and every
/// future edit had to be applied in three places. The builder receives each
/// option and whether it is selected, so the caller keeps control of the
/// label (icon + text, text only, or text with a badge).
struct SegmentedPicker<T>: View where T: Equatable, T: CaseIterable, T: Identifiable {
    /// Options to render, in order. Defaults to `T.allCases`.
    let options: [T]
    /// Currently selected option.
    @Binding var selection: T
    /// Theme for the track, text and selection states.
    let palette: Palette
    /// Height of each segment.
    let height: CGFloat
    /// Corner radius of the individual segments and of the enclosing track
    /// (the track is two points larger so the segments sit inside its stroke).
    let corner: CGFloat
    /// Horizontal padding inside the track.
    let horizontalPadding: CGFloat
    /// Vertical padding inside the track.
    let verticalPadding: CGFloat
    /// Font applied to the label rows.
    let font: Font
    /// Builds the label for an option. `selected` mirrors `option == selection`
    /// and is passed so the caller can style the active segment.
    let label: (T, Bool) -> AnyView
    /// Called when a different option is selected, so callers can clear
    /// derived state (e.g. an error message) exactly when the selection moves.
    let onSelect: ((T) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init<L: View>(
        _ options: [T] = Array(T.allCases),
        selection: Binding<T>,
        palette: Palette,
        height: CGFloat = 25,
        corner: CGFloat = 7,
        horizontalPadding: CGFloat = 3,
        verticalPadding: CGFloat = 2,
        font: Font = .system(size: 10.5, weight: .medium),
        onSelect: ((T) -> Void)? = nil,
        @ViewBuilder label: @escaping (T, Bool) -> L
    ) {
        self.options = options
        self._selection = selection
        self.palette = palette
        self.height = height
        self.corner = corner
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.font = font
        self.onSelect = onSelect
        self.label = { AnyView(label($0, $1)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                        selection = option
                        onSelect?(option)
                    }
                } label: {
                    HStack(spacing: 5) {
                        label(option, selected)
                    }
                    .font(font)
                    .foregroundStyle(selected ? palette.text : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(selected ? palette.cardHover : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                .fill(palette.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                .stroke(palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}