import Foundation

struct RuntimeServiceHostConfiguration: Equatable, Sendable {
    let runtimeVersion: String
    let protocolRange: ProtocolRange
    let operatingMode: RuntimeOperatingMode
    let capabilities: [CapabilityState]
    let services: [RuntimeServiceDescriptor]
    let providers: [RuntimeProviderDescriptor]
    let backgroundState: BackgroundSessionState
    let health: RuntimeServiceHealth

    init(
        runtimeVersion: String,
        protocolRange: ProtocolRange,
        operatingMode: RuntimeOperatingMode,
        capabilities: [CapabilityState],
        services: [RuntimeServiceDescriptor],
        providers: [RuntimeProviderDescriptor] = [],
        backgroundState: BackgroundSessionState = .inactive,
        health: RuntimeServiceHealth = .healthy
    ) {
        self.runtimeVersion = runtimeVersion
        self.protocolRange = protocolRange
        self.operatingMode = operatingMode
        self.capabilities = capabilities
        self.services = services
        self.providers = providers
        self.backgroundState = backgroundState
        self.health = health
    }
}

final class RuntimeServiceHost {
    private var configuration: RuntimeServiceHostConfiguration
    private(set) var state: RuntimeServiceHostState = .stopped
    private(set) var sessionGeneration: Int = 0

    init(configuration: RuntimeServiceHostConfiguration) {
        self.configuration = configuration
    }

    var endpointDescriptor: RuntimeEndpointDescriptor {
        RuntimeEndpointDescriptor(
            endpointID: "\(RuntimeDescriptorFactory.runtimeIdentity).endpoint",
            runtimeIdentity: RuntimeDescriptorFactory.runtimeIdentity,
            protocolRange: configuration.protocolRange
        )
    }

    var descriptor: RuntimeDescriptor {
        RuntimeDescriptorFactory.make(
            runtimeVersion: configuration.runtimeVersion,
            protocolRange: configuration.protocolRange,
            operatingMode: configuration.operatingMode,
            capabilities: configuration.capabilities,
            services: configuration.services
        )
    }

    func start() throws {
        guard state == .stopped || state == .unavailable else {
            throw RuntimeServiceError.operationRejected
        }
        state = .starting
        sessionGeneration += 1
        state = .ready
    }

    func stop() throws {
        guard state != .stopped else { return }
        state = .stopping
        state = .stopped
    }

    func disconnect() {
        guard state != .stopped, state != .stopping else { return }
        state = .unavailable
    }

    func updatePublishedState(
        capabilities: [CapabilityState],
        services: [RuntimeServiceDescriptor],
        providers: [RuntimeProviderDescriptor],
        backgroundState: BackgroundSessionState,
        health: RuntimeServiceHealth
    ) {
        configuration = RuntimeServiceHostConfiguration(
            runtimeVersion: configuration.runtimeVersion,
            protocolRange: configuration.protocolRange,
            operatingMode: configuration.operatingMode,
            capabilities: capabilities,
            services: services,
            providers: providers,
            backgroundState: backgroundState,
            health: health
        )
    }

    func reconnect() throws {
        guard state == .unavailable else {
            throw RuntimeServiceError.operationRejected
        }
        state = .starting
        sessionGeneration += 1
        state = .ready
    }

    func handshake(_ request: RuntimeHandshakeRequest) throws -> RuntimeHandshakeResponse {
        guard state == .ready else {
            throw RuntimeServiceError.runtimeUnavailable
        }
        let negotiated = try RuntimeHandshakeNegotiator.handshake(
            request: request,
            descriptor: descriptor
        )
        return RuntimeHandshakeResponse(
            negotiatedProtocol: negotiated.negotiatedProtocol,
            descriptor: negotiated.descriptor,
            preservedUnknownOptionalCapabilities: negotiated.preservedUnknownOptionalCapabilities,
            sessionGeneration: sessionGeneration,
            providerDescriptors: configuration.providers,
            backgroundState: configuration.backgroundState,
            health: configuration.health
        )
    }
}
