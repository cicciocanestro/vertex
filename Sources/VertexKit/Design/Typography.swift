import SwiftUI

/// Semantic type scale based on system text styles (Dynamic Type).
///
/// All views and shared components use these semantic tokens instead of
/// fixed `.system(size:)` declarations so text scales cleanly with system
/// Dynamic Type and accessibility preferences while preserving the visual
/// hierarchy across the app.
enum Typography {
    // MARK: - Display & Title styles

    static let heroText = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let modalTitleText = Font.system(.title2, design: .rounded).weight(.semibold)
    static let sectionTitleText = Font.system(.title3, design: .rounded).weight(.semibold)
    static let titleText = Font.system(.title3).weight(.semibold)
    static let rowTitleText = Font.system(.headline).weight(.semibold)

    // MARK: - Body & Subheadline styles

    static let bodyLargeSemiboldText = Font.system(.body).weight(.semibold)
    static let bodyLargeRegularText = Font.system(.body)
    static let bodyLargeMediumText = Font.system(.body).weight(.medium)
    static let bodyLargeText = Font.system(.body)
    static let bodySemiboldText = Font.system(.subheadline).weight(.semibold)
    static let bodyMediumText = Font.system(.subheadline).weight(.medium)
    static let bodyText = Font.system(.subheadline)

    // MARK: - Small & Callout styles

    static let smallText = Font.system(.callout)
    static let smallMediumText = Font.system(.callout).weight(.medium)
    static let smallSemiboldText = Font.system(.callout).weight(.semibold)
    static let smallRoundedMediumText = Font.system(.callout, design: .rounded).weight(.medium)
    static let smallRoundedSemiboldText = Font.system(.callout, design: .rounded).weight(.semibold)
    static let smallMonoText = Font.system(.callout, design: .monospaced)
    static let rowMetaText = Font.system(.subheadline, design: .rounded)

    // MARK: - Caption styles

    static let captionText = Font.system(.caption)
    static let captionSmallText = Font.system(.caption)
    static let captionMediumText = Font.system(.caption).weight(.medium)
    static let captionSemiboldText = Font.system(.caption).weight(.semibold)
    static let captionMediumRoundedText = Font.system(.caption, design: .rounded).weight(.medium)
    static let captionRegularRoundedText = Font.system(.caption, design: .rounded)
    static let captionMonoText = Font.system(.caption, design: .monospaced)
    static let captionMonoMediumText = Font.system(.caption, design: .monospaced).weight(.medium)

    // MARK: - Footnote & Micro styles

    static let microText = Font.system(.caption2)
    static let microMediumText = Font.system(.caption2).weight(.medium)
    static let microSemiboldText = Font.system(.caption2).weight(.semibold)
    static let microRoundedText = Font.system(.caption2, design: .rounded)
    static let microRoundedMediumText = Font.system(.caption2, design: .rounded).weight(.medium)
    static let microRoundedSemiboldText = Font.system(.caption2, design: .rounded).weight(.semibold)
    static let captionTinyText = Font.system(.caption2)
    static let captionTinyNarrowText = Font.system(.caption2)
    static let captionTinySemiboldText = Font.system(.caption2).weight(.semibold)
    static let captionTinyMonoText = Font.system(.caption2, design: .monospaced)
    static let captionMicroSemiboldText = Font.system(.caption2).weight(.semibold)
    static let badgeText = Font.system(.caption2).weight(.semibold)

    // MARK: - Decorative & Hero Icons

    static let iconHero = Font.system(size: 34, weight: .light)
    static let iconDrop = Font.system(size: 30, weight: .light)
    static let iconLarge = Font.system(size: 26, weight: .light)
    static let iconMedium = Font.system(size: 24, weight: .light)
    static let iconSmall = Font.system(size: 23, weight: .light)
    static let iconDoc = Font.system(size: 22, weight: .light)
    static let iconInline = Font.system(.caption2).weight(.bold)

    // MARK: - Dynamic Helpers

    static func chipLabelText(selected: Bool) -> Font {
        Font.system(.subheadline).weight(selected ? .semibold : .medium)
    }

    static func sidebarItemText(selected: Bool) -> Font {
        Font.system(.subheadline).weight(selected ? .semibold : .regular)
    }

    static func speedIcon(compact: Bool) -> Font {
        Font.system(compact ? .caption2 : .caption).weight(.bold)
    }

    static func speedValue(compact: Bool) -> Font {
        Font.system(compact ? .caption : .callout, design: .rounded).weight(.medium)
    }

    static func proportional(size: CGFloat, weight: Font.Weight = .semibold, design: Font.Design = .default) -> Font {
        Font.system(size: size, weight: weight, design: design)
    }
}
