import Foundation

struct RuntimeRepositoryProviderDescriptor: Equatable, Hashable, Codable, Sendable {
    let providerID: String
    let providerKind: ProviderKind
    let health: RuntimeServiceHealth
    let capabilities: Set<CapabilityIdentifier>
    let trust: RuntimeRepositoryTrust
    let provenance: RuntimeRepositoryProvenance

    init(
        providerID: String,
        providerKind: ProviderKind,
        health: RuntimeServiceHealth,
        capabilities: Set<CapabilityIdentifier>,
        trust: RuntimeRepositoryTrust = .unverified,
        provenance: RuntimeRepositoryProvenance = RuntimeRepositoryProvenance(
            distribution: "unknown",
            sourceIdentifier: "unknown",
            iconURL: nil,
            depictionURL: nil
        )
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.health = health
        self.capabilities = capabilities
        self.trust = trust
        self.provenance = provenance
    }
}
