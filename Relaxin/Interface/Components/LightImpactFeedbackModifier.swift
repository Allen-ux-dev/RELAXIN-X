import SwiftUI
import UIKit

struct LightImpactFeedbackModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let shouldPlay: (Trigger, Trigger) -> Bool
    @State private var previousTrigger: Trigger

    init(
        trigger: Trigger,
        shouldPlay: @escaping (Trigger, Trigger) -> Bool = { _, _ in true }
    ) {
        self.trigger = trigger
        self.shouldPlay = shouldPlay
        _previousTrigger = State(initialValue: trigger)
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.sensoryFeedback(
                .impact(weight: .light),
                trigger: trigger,
                condition: shouldPlay
            )
        } else {
            content.onChange(of: trigger) { newTrigger in
                let oldTrigger = previousTrigger
                previousTrigger = newTrigger
                guard shouldPlay(oldTrigger, newTrigger) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}
