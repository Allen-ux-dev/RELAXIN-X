import Foundation
import UIKit

enum HardwareButtonAction {
    case primary
    case secondary
}

enum HardwareButtonEvent {
    case began(HardwareButtonAction)
    case ended(HardwareButtonAction)
    case cancelled
}

@MainActor
final class HardwareButtonEventMonitor {
    enum Usage {
        case generalInterface
        /// Valid only while the app has an active camera capture session.
        case activeCameraCapture
    }

    typealias Handler = (HardwareButtonEvent) -> Void

    @MainActor
    protocol Backend: AnyObject {
        func start()
        func stop()
    }

    private let backend: any Backend

    init(
        attachedTo view: UIView,
        usage: Usage,
        handler: @escaping Handler
    ) {
        if case .activeCameraCapture = usage,
           #available(iOS 17.2, *)
        {
            backend = NativeBackend(view: view, handler: handler)
            AppLog.info(Self.self, "using native capture event backend")
        } else {
            backend = PrivateBackend(handler: handler)
            AppLog.info(Self.self, "using private volume button backend")
        }
    }

    func start() {
        backend.start()
    }

    func stop() {
        backend.stop()
    }
}
