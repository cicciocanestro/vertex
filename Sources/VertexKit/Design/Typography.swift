import SwiftUI

/// Semantic type scale used by the shared components and the main views.
///
/// The sizes are grouped in six steps (8, 9, 10, 10.5, 11, 12) plus the two
/// display sizes. The names are kept from the previous version so the call
/// sites did not have to change, but the values that differed by 0.2–0.5 pt
/// (8.5 / 9.2 / 9.8 / 12.5) are collapsed: steps that close are not perceivable
/// and only made the hierarchy noisy.
///
/// A future redesign should also replace the fixed sizes with the system text
/// styles (`.caption`, `.body`, …) to get Dynamic Type and accessibility
/// scaling; that requires touching every view, so it stays a separate change.
enum Typography {
    // Step 8 — badges and micro labels.
    static let badge = Font.system(size: 8, weight: .semibold)
    static let captionMicroSemibold = Font.system(size: 9, weight: .semibold)

    // Step 9 — the densest informative text.
    static let captionTiny = Font.system(size: 9)
    static let captionTinyNarrow = Font.system(size: 9)
    static let captionTinySemibold = Font.system(size: 9, weight: .semibold)
    static let micro = Font.system(size: 9.5)
    static let microMedium = Font.system(size: 9.5, weight: .medium)
    static let microSemibold = Font.system(size: 9.5, weight: .semibold)

    // Step 10 — captions, subtitles, secondary rows.
    static let caption = Font.system(size: 10)
    static let captionMedium = Font.system(size: 10, weight: .medium)
    static let captionMediumRounded = Font.system(size: 10, weight: .medium, design: .rounded)
    static let captionMono = Font.system(size: 10, design: .monospaced)
    static let captionSmall = Font.system(size: 10)

    // Step 10.5 — small controls and labels.
    static let small = Font.system(size: 10.5)
    static let smallMedium = Font.system(size: 10.5, weight: .medium)
    static let smallMono = Font.system(size: 10.5, design: .monospaced)

    // Step 11 — body text inside cards and settings rows.
    static let body = Font.system(size: 11)
    static let bodyMedium = Font.system(size: 11, weight: .medium)
    static let bodySemibold = Font.system(size: 11, weight: .semibold)

    // Step 11.5 — emphasised body (setting titles, dialog rows).
    static let bodyLarge = Font.system(size: 11.5)
    static let bodyLargeMedium = Font.system(size: 11.5, weight: .medium)

    // Step 12 — readable text: empty states, descriptions.
    static let bodyLargeRegular = Font.system(size: 12)
    static let bodyLargeSemibold = Font.system(size: 12, weight: .semibold)

    // Row typography. A torrent name must win against the metadata below it,
    // so it sits one step above the body text.
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let rowMeta = Font.system(size: 10.5, weight: .regular, design: .rounded)

    // Display.
    static let title = Font.system(size: 13.5, weight: .semibold)
    static let modalTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let hero = Font.system(size: 22, weight: .semibold, design: .rounded)

    // Decorative icons.
    static let iconLarge = Font.system(size: 26, weight: .light)
    static let iconMedium = Font.system(size: 24, weight: .light)
    static let iconSmall = Font.system(size: 23, weight: .light)
}
