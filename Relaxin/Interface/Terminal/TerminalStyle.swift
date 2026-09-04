import Foundation

enum TerminalStyle {
    /// Clears both the viewport and saved lines before drawing a snapshot.
    static let clearAndHome = "\u{1B}[3J\u{1B}[2J\u{1B}[H"
    static let hideCursor = "\u{1B}[?25l"
    static let showCursor = "\u{1B}[?25h"

    private static let reset = "\u{1B}[0m"
    private static let stringTerminator = "\u{1B}\\"
    private static let cursorBackward = "\u{1B}[D"
    private static let cursorForward = "\u{1B}[C"

    static func bold(_ text: String) -> String {
        "\u{1B}[1m\(text)\(reset)"
    }

    /// Default terminal foreground (solid black in light / white in dark).
    static func foreground(_ text: String) -> String {
        "\u{1B}[39m\(text)\(reset)"
    }

    static func dim(_ text: String) -> String {
        "\u{1B}[90m\(text)\(reset)"
    }

    static func accent(_ text: String) -> String {
        "\u{1B}[32m\(text)\(reset)"
    }

    static func danger(_ text: String) -> String {
        "\u{1B}[31m\(text)\(reset)"
    }

    static func white(_ text: String) -> String {
        "\u{1B}[97m\(text)\(reset)"
    }

    static func hyperlink(_ text: String, destination: URL) -> String {
        // SwiftTerm closes OSC 8 ranges inclusively at the cursor cell, so close over the final glyph and restore the cursor.
        "\u{1B}]8;;\(destination.absoluteString)\(stringTerminator)"
            + text
            + cursorBackward
            + "\u{1B}]8;;\(stringTerminator)"
            + cursorForward
    }
}
