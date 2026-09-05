import Foundation

struct RuntimeProviderDescriptor: Equatable, Hashable, Codable, Sendable {
    let providerID: String
    let serviceID: String
    let providerKind: ProviderKind
    let health: RuntimeServiceHealth
    let capabilities: [CapabilityState]
    let sessionGeneration: Int

    var isUsable: Bool {
        health != .unavailable && health != .stopping
    }
}
