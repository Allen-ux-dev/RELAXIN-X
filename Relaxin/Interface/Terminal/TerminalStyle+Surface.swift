import SwiftUI
import UIKit

extension TerminalStyle {
    static let presenterFont = Theme.uiFont

    @MainActor static func configure(
        _ view: TerminalView,
        colorScheme: SwiftUI.ColorScheme
    ) {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.linkReporting = .explicit
        view.linkHighlightMode = .always
        view.allowMouseReporting = false
        applyColors(to: view, colorScheme: colorScheme)
    }

    @MainActor static func applyColors(
        to view: TerminalView,
        colorScheme: SwiftUI.ColorScheme
    ) {
        let traits = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )
        view.nativeBackgroundColor = .clear
        view.nativeForegroundColor = UIColor.label.resolvedColor(with: traits)
        view.caretColor = UIColor.accent.resolvedColor(with: traits)
        view.caretTextColor = UIColor.systemBackground.resolvedColor(with: traits)
    }
}
