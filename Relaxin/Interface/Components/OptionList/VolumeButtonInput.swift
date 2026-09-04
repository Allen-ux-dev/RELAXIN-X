import SwiftUI
import UIKit

enum VolumeButtonDirection {
    case up
    case down
}

/// Converts raw volume-button events into menu commands.
@MainActor
struct VolumeButtonInput: UIViewRepresentable {
    let onTap: (VolumeButtonDirection) -> Void
    let onLongPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onLongPress: onLongPress
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        context.coordinator.startMonitoring(attachedTo: view)
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onTap: (VolumeButtonDirection) -> Void
        var onLongPress: () -> Void

        private static let longPressDuration: TimeInterval = 0.5
        private var eventMonitor: HardwareButtonEventMonitor?
        private var longPressTimer: Timer?
        private var pressedDirection: VolumeButtonDirection?

        init(
            onTap: @escaping (VolumeButtonDirection) -> Void,
            onLongPress: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onLongPress = onLongPress
            super.init()
        }

        func startMonitoring(attachedTo view: UIView) {
            let eventMonitor = HardwareButtonEventMonitor(
                attachedTo: view,
                usage: .generalInterface
            ) { [weak self] event in
                self?.handle(event)
            }
            self.eventMonitor = eventMonitor
            eventMonitor.start()
        }

        func stopMonitoring() {
            cancelPress()
            eventMonitor?.stop()
            eventMonitor = nil
        }

        private func beginPress(_ direction: VolumeButtonDirection) {
            guard pressedDirection != direction else { return }
            cancelPress()

            pressedDirection = direction
            AppLog.info(
                VolumeButtonInput.self,
                "volume button down direction=\(direction)"
            )
            longPressTimer = Timer.scheduledTimer(
                timeInterval: Self.longPressDuration,
                target: self,
                selector: #selector(longPressTimerFired(_:)),
                userInfo: nil,
                repeats: false
            )
        }

        private func endPress(_ direction: VolumeButtonDirection) {
            guard pressedDirection == direction else { return }
            let isTap = longPressTimer != nil
            cancelPress()
            AppLog.info(
                VolumeButtonInput.self,
                "volume button up direction=\(direction) tap=\(isTap ? 1 : 0)"
            )
            if isTap {
                onTap(direction)
            }
        }

        private func cancelPress() {
            longPressTimer?.invalidate()
            longPressTimer = nil
            pressedDirection = nil
        }

        private func handle(_ event: HardwareButtonEvent) {
            switch event {
            case let .began(action):
                beginPress(direction(for: action))
            case let .ended(action):
                endPress(direction(for: action))
            case .cancelled:
                cancelPress()
            }
        }

        private func direction(
            for action: HardwareButtonAction
        ) -> VolumeButtonDirection {
            switch action {
            case .primary:
                .down
            case .secondary:
                .up
            }
        }

        @objc private func longPressTimerFired(_: Timer) {
            guard let pressedDirection else { return }
            longPressTimer = nil
            AppLog.info(
                VolumeButtonInput.self,
                "volume button long press direction=\(pressedDirection)"
            )
            onLongPress()
        }
    }
}
