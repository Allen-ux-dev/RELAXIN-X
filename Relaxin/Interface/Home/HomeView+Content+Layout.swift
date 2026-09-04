import CoreGraphics

enum HomeContentLayout {
    static let minimumTopSpacing: CGFloat = 32
    static let compactTopSpacing: CGFloat = 12
    static let terminalHeight: CGFloat = 300
    static let minimumMenuViewportHeight: CGFloat = 150
    static let minimumBottomSpacing: CGFloat = 32
    static let compactBottomSpacing: CGFloat = 20
    static let terminalLineHeight: CGFloat = 18
    static let terminalVerticalPadding: CGFloat = 12

    static func creditsTerminalHeight(lineCount: Int) -> CGFloat {
        max(
            terminalHeight,
            CGFloat(max(1, lineCount)) * terminalLineHeight + terminalVerticalPadding
        )
    }

    static func minimumMenuLayoutHeight(terminalHeight: CGFloat) -> CGFloat {
        minimumTopSpacing
            + terminalHeight
            + minimumMenuViewportHeight
            + minimumBottomSpacing
    }
}
