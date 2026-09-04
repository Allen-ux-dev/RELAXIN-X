import Foundation

final class PrismRuntimeBridgeBootstrap: @unchecked Sendable {
    static let shared = PrismRuntimeBridgeBootstrap()

    private let lock = NSLock()
    private var server: PrismUnixSocketRuntimeServiceServer?

    private init() {}

    func start(
        serviceVersion: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard server == nil else { return }

        let host = PrismBuild52RuntimeDefaults.makeHandshakeOnlyHost(
            serviceVersion: serviceVersion
        )
        let processor = PrismRuntimeServiceFrameProcessor(host: host)
        let candidate = PrismUnixSocketRuntimeServiceServer(
            path: PrismBuild52RuntimeEndpoint.socketPath(environment: environment),
            processor: processor
        )
        try candidate.start()
        server = candidate
    }

    func stop() {
        lock.lock()
        let active = server
        server = nil
        lock.unlock()
        active?.stop()
    }
}
