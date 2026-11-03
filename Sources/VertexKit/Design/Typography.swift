import SwiftUI

/// Semantic type scale used by the shared components and the main views.
/// Values match the previous hardcoded sizes, so the refactor is visually
/// neutral and the remaining one-off sizes are explicit.
enum Typography {
    static let micro = Font.system(size: 9.5)
    static let microMedium = Font.system(size: 9.5, weight: .medium)
    static let microSemibold = Font.system(size: 9.5, weight: .semibold)
    static let badge = Font.system(size: 7.5, weight: .semibold)

    static let captionTiny = Font.system(size: 9)
    static let captionTinyNarrow = Font.system(size: 9.2)
    static let captionTinySemibold = Font.system(size: 9, weight: .semibold)
    static let captionMicroSemibold = Font.system(size: 8.5, weight: .semibold)
    static let captionSmall = Font.system(size: 9.8)
    static let caption = Font.system(size: 10)
    static let captionMedium = Font.system(size: 10, weight: .medium)
    static let captionMediumRounded = Font.system(size: 10, weight: .medium, design: .rounded)
    static let captionMono = Font.system(size: 10, design: .monospaced)

    static let small = Font.system(size: 10.5)
    static let smallMedium = Font.system(size: 10.5, weight: .medium)
    static let smallMono = Font.system(size: 10.5, design: .monospaced)

    static let body = Font.system(size: 11)
    static let bodyMedium = Font.system(size: 11, weight: .medium)
    static let bodySemibold = Font.system(size: 11, weight: .semibold)
    static let bodyLarge = Font.system(size: 11.5)
    static let bodyLargeMedium = Font.system(size: 11.5, weight: .medium)
    static let bodyLargeRegular = Font.system(size: 12.5)
    static let bodyLargeSemibold = Font.system(size: 12.5, weight: .semibold)

    static let title = Font.system(size: 13.5, weight: .semibold)
    static let modalTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
    static let hero = Font.system(size: 22, weight: .semibold, design: .rounded)

    static let iconLarge = Font.system(size: 26, weight: .light)
    static let iconMedium = Font.system(size: 24, weight: .light)
    static let iconSmall = Font.system(size: 23, weight: .light)
}
