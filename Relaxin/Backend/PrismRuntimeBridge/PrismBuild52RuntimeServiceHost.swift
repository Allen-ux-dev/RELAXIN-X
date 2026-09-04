import Foundation

struct PrismBuild52RuntimeServiceHost: Sendable {
    let runtimeIdentity: String
    let displayName: String
    let serviceVersion: String
    let supportedProtocolVersions: Set<Int>
    let providerKind: PrismRuntimeServiceProviderKind
    let priority: Int
    let capabilityStates: [PrismCapabilityIdentifier: PrismCapabilityState]
    let health: PrismProviderHealth
    let backgroundSessionState: PrismRuntimeBackgroundSessionState
    let metadata: [String: String]

    init(
        runtimeIdentity: String,
        displayName: String,
        serviceVersion: String,
        supportedProtocolVersions: [Int],
        providerKind: PrismRuntimeServiceProviderKind,
        priority: Int,
        capabilityStates: [PrismCapabilityState],
        health: PrismProviderHealth,
        backgroundSessionState: PrismRuntimeBackgroundSessionState,
        metadata: [String: String]
    ) {
        self.runtimeIdentity = runtimeIdentity
        self.displayName = displayName
        self.serviceVersion = serviceVersion
        self.supportedProtocolVersions = Set(supportedProtocolVersions)
        self.providerKind = providerKind
        self.priority = priority
        self.capabilityStates = Dictionary(uniqueKeysWithValues: capabilityStates.map { ($0.identifier, $0) })
        self.health = health
        self.backgroundSessionState = backgroundSessionState
        self.metadata = metadata
    }

    func handleJSON(_ requestData: Data) throws -> Data {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let request: PrismRuntimeServiceRequest
        do {
            request = try decoder.decode(PrismRuntimeServiceRequest.self, from: requestData)
        } catch {
            return try encoder.encode(
                PrismRuntimeServiceResponse.rejected(reason: "operationRejected: malformed runtime service request")
            )
        }

        switch request {
        case let .handshake(helloRequest):
            let common = supportedProtocolVersions.intersection(helloRequest.supportedProtocolVersions)
            guard let selected = common.max() else {
                return try encoder.encode(
                    PrismRuntimeServiceResponse.rejected(reason: "protocolIncompatible: no common protocol version")
                )
            }

            let hello = PrismRuntimeServiceHello(
                runtimeIdentity: runtimeIdentity,
                displayName: displayName,
                serviceVersion: serviceVersion,
                selectedProtocolVersion: selected,
                providerKind: providerKind,
                priority: priority,
                capabilityStates: capabilityStates,
                health: health,
                backgroundSessionState: backgroundSessionState,
                metadata: metadata
            )
            return try encoder.encode(PrismRuntimeServiceResponse.hello(hello))

        case let .unsupported(name):
            return try encoder.encode(
                PrismRuntimeServiceResponse.rejected(
                    reason: "providerUnavailable: RELAXIN-X backend is not wired for \(name)"
                )
            )
        }
    }
}
