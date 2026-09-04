import AVKit
import UIKit

@available(iOS 17.2, *)
extension HardwareButtonEventMonitor {
    @MainActor
    final class NativeBackend: Backend {
        private let handler: Handler
        private let interaction: AVCaptureEventInteraction
        private weak var view: UIView?

        init(
            view: UIView,
            handler: @escaping Handler
        ) {
            self.view = view
            self.handler = handler
            interaction = AVCaptureEventInteraction(
                primary: { event in
                    Self.forward(event, action: .primary, to: handler)
                },
                secondary: { event in
                    Self.forward(event, action: .secondary, to: handler)
                }
            )
        }

        func start() {
            guard interaction.view == nil, let view else { return }
            view.addInteraction(interaction)
            AppLog.info(
                HardwareButtonEventMonitor.self,
                "native capture events enabled"
            )
        }

        func stop() {
            guard let attachedView = interaction.view else { return }
            handler(.cancelled)
            attachedView.removeInteraction(interaction)
            AppLog.info(
                HardwareButtonEventMonitor.self,
                "native capture events disabled"
            )
        }

        private static func forward(
            _ event: AVCaptureEvent,
            action: HardwareButtonAction,
            to handler: Handler
        ) {
            switch event.phase {
            case .began:
                handler(.began(action))
            case .ended:
                handler(.ended(action))
            case .cancelled:
                handler(.cancelled)
            @unknown default:
                handler(.cancelled)
            }
        }
    }
}
