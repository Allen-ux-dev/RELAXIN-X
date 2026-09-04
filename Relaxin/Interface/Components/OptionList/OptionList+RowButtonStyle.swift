import SwiftUI

extension OptionList {
    /// Compact row whose marker keeps a stable four-point gap from the label.
    /// Touch-down only moves the list's single selection.
    struct RowButtonStyle: ButtonStyle {
        let isSelected: Bool
        let isLoading: Bool
        let accent: SwiftUI.Color
        let onPress: () -> Void

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: OptionListLayout.markerSpacing) {
                Group {
                    if isLoading {
                        LoadingMarker(color: accent)
                    } else if isSelected {
                        SelectionMarker(color: accent)
                    } else {
                        SwiftUI.Color.clear
                    }
                }
                .frame(width: OptionListLayout.markerWidth)

                configuration.label
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .transaction { $0.animation = nil }
            .onChange(of: configuration.isPressed) { isPressed in
                guard isPressed else { return }
                onPress()
            }
        }
    }

    private struct LoadingMarker: View {
        let color: SwiftUI.Color

        var body: some View {
            TimelineView(.animation) { context in
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1)
                Image(systemName: "hourglass")
                    .font(.system(size: Theme.fontSize * 0.75))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(progress * 360))
            }
            .accessibilityHidden(true)
        }
    }

    private struct SelectionMarker: View {
        let color: SwiftUI.Color

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5)
                Image(systemName: "play.fill")
                    .font(.system(size: Theme.fontSize * 0.5))
                    .foregroundStyle(color)
                    .opacity(tick.isMultiple(of: 2) ? 1 : 0)
            }
            .accessibilityHidden(true)
        }
    }
}
