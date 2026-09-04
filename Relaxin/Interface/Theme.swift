import SwiftUI
import UIKit

enum Theme {
    static let accent = SwiftUI.Color(.accent)
    static let foreground = SwiftUI.Color.primary
    static let background = SwiftUI.Color(uiColor: .systemBackground)
    static let failureBackground = SwiftUI.Color(red: 0.72, green: 0, blue: 0)

    static let pagePadding: CGFloat = 24

    static let fontSize: CGFloat = 14
    static let font = Font.system(size: fontSize, weight: .regular, design: .monospaced)
    static let uiFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
}
