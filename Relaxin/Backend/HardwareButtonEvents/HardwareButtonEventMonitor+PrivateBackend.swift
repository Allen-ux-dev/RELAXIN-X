import Darwin
import UIKit

extension HardwareButtonEventMonitor {
    @MainActor
    final class PrivateBackend: NSObject, Backend {
        private static let volumeEventsSelector = NSSelectorFromString(
            "setWantsVolumeButtonEvents:"
        )
        private static let volumeUpButtonDown = Notification.Name(
            "_UIApplicationVolumeUpButtonDownNotification"
        )
        private static let volumeUpButtonUp = Notification.Name(
            "_UIApplicationVolumeUpButtonUpNotification"
        )
        private static let volumeDownButtonDown = Notification.Name(
            "_UIApplicationVolumeDownButtonDownNotification"
        )
        private static let volumeDownButtonUp = Notification.Name(
            "_UIApplicationVolumeDownButtonUpNotification"
        )
        private static var activeCaptureCount = 0
        private static var volumeControllerDataSource: NSObject?

        private static let mediaPlayerFrameworkHandle = dlopen(
            "/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer",
            RTLD_LAZY | RTLD_LOCAL
        )

        private let handler: Handler
        private var isCapturing = false

        init(handler: @escaping Handler) {
            self.handler = handler
            super.init()
        }

        func start() {
            registerNotifications()
            updateCaptureState()
        }

        func stop() {
            handler(.cancelled)
            endCapturing()
            NotificationCenter.default.removeObserver(self)
        }

        private func updateCaptureState() {
            if UIApplication.shared.applicationState == .active {
                beginCapturing()
            } else {
                endCapturing()
            }
        }

        private func registerNotifications() {
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(volumeUpButtonPressed(_:)),
                name: Self.volumeUpButtonDown,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(volumeUpButtonReleased(_:)),
                name: Self.volumeUpButtonUp,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(volumeDownButtonPressed(_:)),
                name: Self.volumeDownButtonDown,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(volumeDownButtonReleased(_:)),
                name: Self.volumeDownButtonUp,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(applicationWillResignActive(_:)),
                name: UIApplication.willResignActiveNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive(_:)),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        private func beginCapturing() {
            guard !isCapturing else { return }

            if Self.activeCaptureCount == 0 {
                if Self.volumeControllerDataSource == nil {
                    Self.volumeControllerDataSource =
                        Self.makeVolumeControllerDataSource()
                }
                guard Self.setEventRegistration(true) else { return }
            }

            Self.activeCaptureCount += 1
            isCapturing = true
        }

        private func endCapturing() {
            guard isCapturing else { return }
            guard Self.activeCaptureCount > 0 else {
                isCapturing = false
                return
            }
            Self.activeCaptureCount -= 1
            if Self.activeCaptureCount == 0 {
                Self.setEventRegistration(false)
            }
            isCapturing = false
        }

        private static func makeVolumeControllerDataSource() -> NSObject? {
            guard mediaPlayerFrameworkHandle != nil else {
                let reason = dlerror().map { String(cString: $0) }
                    ?? "unknown error"
                AppLog.error(
                    HardwareButtonEventMonitor.self,
                    "MediaPlayer framework load failed: \(reason)"
                )
                return nil
            }
            AppLog.info(
                HardwareButtonEventMonitor.self,
                "MediaPlayer framework loaded"
            )
            guard let dataSourceType = NSClassFromString(
                "MPVolumeControllerSystemDataSource"
            ) as? NSObject.Type else {
                AppLog.error(
                    HardwareButtonEventMonitor.self,
                    "MPVolumeControllerSystemDataSource unavailable iOS=\(UIDevice.current.systemVersion)"
                )
                return nil
            }
            let dataSource = dataSourceType.init()
            AppLog.info(
                HardwareButtonEventMonitor.self,
                "MPVolumeControllerSystemDataSource initialized iOS=\(UIDevice.current.systemVersion)"
            )
            return dataSource
        }

        @discardableResult
        private static func setEventRegistration(_ enabled: Bool) -> Bool {
            typealias SetVolumeButtonEvents = @convention(c) (
                AnyObject,
                Selector,
                Bool
            ) -> Void

            guard let method = class_getInstanceMethod(
                UIApplication.self,
                volumeEventsSelector
            ) else {
                AppLog.error(
                    HardwareButtonEventMonitor.self,
                    "setWantsVolumeButtonEvents: unavailable iOS=\(UIDevice.current.systemVersion)"
                )
                return false
            }
            let setVolumeButtonEvents = unsafeBitCast(
                method_getImplementation(method),
                to: SetVolumeButtonEvents.self
            )
            setVolumeButtonEvents(
                UIApplication.shared,
                Self.volumeEventsSelector,
                enabled
            )
            AppLog.info(
                HardwareButtonEventMonitor.self,
                "private volume button events \(enabled ? "enabled" : "disabled")"
            )
            return true
        }

        @objc private func volumeUpButtonPressed(_: Notification) {
            guard isCapturing else { return }
            handler(.began(.secondary))
        }

        @objc private func volumeUpButtonReleased(_: Notification) {
            guard isCapturing else { return }
            handler(.ended(.secondary))
        }

        @objc private func volumeDownButtonPressed(_: Notification) {
            guard isCapturing else { return }
            handler(.began(.primary))
        }

        @objc private func volumeDownButtonReleased(_: Notification) {
            guard isCapturing else { return }
            handler(.ended(.primary))
        }

        @objc private func applicationWillResignActive(_: Notification) {
            handler(.cancelled)
            endCapturing()
        }

        @objc private func applicationDidBecomeActive(_: Notification) {
            updateCaptureState()
        }
    }
}
