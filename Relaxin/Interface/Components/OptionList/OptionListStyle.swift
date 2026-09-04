import SwiftUI

enum OptionListLayout {
    static let markerWidth = Theme.fontSize
    static let markerSpacing: CGFloat = 4
    static let markerGutter = markerWidth + markerSpacing
}

struct OptionListStyle {
    let foreground: SwiftUI.Color
    let secondaryForeground: SwiftUI.Color
    let accent: SwiftUI.Color

    static let standard = OptionListStyle(
        foreground: Theme.foreground,
        secondaryForeground: .secondary,
        accent: Theme.accent
    )

    static let failure = OptionListStyle(
        foreground: .white,
        secondaryForeground: .white,
        accent: .white
    )
}
