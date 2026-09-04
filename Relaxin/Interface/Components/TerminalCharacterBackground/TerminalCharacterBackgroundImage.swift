import SwiftUI
import UIKit

/// Rasterizes the terminal character pattern once, at screen resolution.
///
/// The pattern is static, so it is drawn a single time at launch and scaled with
/// aspect fill afterwards instead of being re-resolved every frame.
///
/// Glyphs are baked as a template mask rather than in a concrete color, so the
/// one bitmap keeps following `Theme.foreground` across appearance changes.
@MainActor
enum TerminalCharacterBackgroundImage {
    private static var cached: UIImage?

    /// Warms the bitmap before the first frame that needs it.
    static func prepare() {
        _ = current
    }

    static var current: UIImage {
        if let cached { return cached }
        let image = render()
        cached = image
        return image
    }

    private static func render() -> UIImage {
        // One main-thread screen snapshot feeds both the canvas extent and the
        // point-to-pixel conversion below.
        let screen = UIScreen.main
        let pixelSize = screen.nativeBounds.size
        let scale = screen.nativeScale

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            drawCharacters(size: pixelSize, scale: scale)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Every input is in pixels; point-based theme metrics are converted with `scale`.
    private static func drawCharacters(size: CGSize, scale: CGFloat) {
        let fontSize = Theme.fontSize * scale
        let rowHeight = fontSize * 1.45
        let columnWidth = fontSize * 5
        let rowCount = Int(size.height / rowHeight) + 3
        let columnCount = Int(size.width / columnWidth) + 3

        let characters = NSAttributedString(
            string: "relaxin",
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: UIColor.white,
            ]
        )
        // `draw(at:)` anchors top-left, the pattern anchors leading-center.
        let verticalAnchorOffset = characters.size().height / 2

        for row in 0 ..< rowCount {
            for column in 0 ..< columnCount {
                let x = CGFloat(column) * columnWidth - columnWidth
                let y = CGFloat(row) * rowHeight - rowHeight
                let normalizedX = x / max(size.width, 1) * 2 - 1
                let normalizedY = y / max(size.height, 1) * 2 - 1
                let radialDistance = hypot(normalizedX, normalizedY)
                let horizontalWarp = sin(normalizedY * 7) * 7 * scale
                let verticalWarp = sin(radialDistance * 8) * 10 * scale

                characters.draw(
                    at: CGPoint(
                        x: x + horizontalWarp,
                        y: y + verticalWarp - verticalAnchorOffset
                    )
                )
            }
        }
    }
}
