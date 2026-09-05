import Foundation

struct RuntimeHandshakeResponse: Equatable, Codable, Sendable {
    let negotiatedProtocol: Int
    let descriptor: RuntimeDescriptor
    let preservedUnknownOptionalCapabilities: Set<CapabilityIdentifier>
    let sessionGeneration: Int
    let providerDescriptors: [RuntimeProviderDescriptor]
    let backgroundState: BackgroundSessionState
    let health: RuntimeServiceHealth

    init(
        negotiatedProtocol: Int,
        descriptor: RuntimeDescriptor,
        preservedUnknownOptionalCapabilities: Set<CapabilityIdentifier>,
        sessionGeneration: Int = 0,
        providerDescriptors: [RuntimeProviderDescriptor] = [],
        backgroundState: BackgroundSessionState = .inactive,
        health: RuntimeServiceHealth = .healthy
    ) {
        self.negotiatedProtocol = negotiatedProtocol
        self.descriptor = descriptor
        self.preservedUnknownOptionalCapabilities = preservedUnknownOptionalCapabilities
        self.sessionGeneration = sessionGeneration
        self.providerDescriptors = providerDescriptors
        self.backgroundState = backgroundState
        self.health = health
    }
}
