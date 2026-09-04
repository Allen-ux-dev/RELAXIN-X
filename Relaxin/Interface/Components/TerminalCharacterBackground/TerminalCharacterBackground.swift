import SwiftUI

struct TerminalCharacterBackground: View {
    let rendersActively: Bool

    var body: some View {
        Group {
            if rendersActively {
                ActiveTerminalCharacterBackground()
            } else {
                StaticTerminalCharacterBackground()
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ActiveTerminalCharacterBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        // Reduce visual motion without pausing the graphics work needed while
        // the engine is running.
        TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
            let phase = reducesMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate * 0.18

            Canvas(rendersAsynchronously: true) { context, size in
                drawCharacters(in: context, size: size, phase: phase)
            }
        }
    }

    private func drawCharacters(
        in context: GraphicsContext,
        size: CGSize,
        phase: TimeInterval
    ) {
        let rowHeight = Theme.fontSize * 1.45
        let columnWidth = Theme.fontSize * 5
        let rowCount = Int(size.height / rowHeight) + 3
        let columnCount = Int(size.width / columnWidth) + 3
        let characters = context.resolve(
            Text(verbatim: "relaxin")
                .font(Theme.font)
                .foregroundColor(Theme.foreground)
        )

        for row in 0 ..< rowCount {
            for column in 0 ..< columnCount {
                let x = CGFloat(column) * columnWidth - columnWidth
                let y = CGFloat(row) * rowHeight - rowHeight
                let normalizedX = x / max(size.width, 1) * 2 - 1
                let normalizedY = y / max(size.height, 1) * 2 - 1
                let radialDistance = hypot(normalizedX, normalizedY)
                let horizontalWarp = sin(normalizedY * 7 + phase) * 7
                let verticalWarp = sin(radialDistance * 8 - phase) * 10

                context.draw(
                    characters,
                    at: CGPoint(
                        x: x + horizontalWarp,
                        y: y + verticalWarp
                    ),
                    anchor: .leading
                )
            }
        }
    }
}

private struct StaticTerminalCharacterBackground: View {
    var body: some View {
        SwiftUI.Color.clear
            .overlay {
                Image(uiImage: TerminalCharacterBackgroundImage.current)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .foregroundStyle(Theme.foreground)
            }
    }
}
