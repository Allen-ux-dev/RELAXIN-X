import Foundation

enum PrismBuild52RuntimeDefaults {
    static let runtimeIdentity = "dev.relaxin.runtime"
    static let serviceID = "dev.relaxin.service.runtime"
    static let supportedProtocolVersions: [Int] = [1]

    static func makeHandshakeOnlyHost(serviceVersion: String) -> PrismBuild52RuntimeServiceHost {
        PrismBuild52RuntimeServiceHost(
            runtimeIdentity: runtimeIdentity,
            displayName: "RELAXIN-X Runtime",
            serviceVersion: serviceVersion,
            supportedProtocolVersions: supportedProtocolVersions,
            providerKind: .native,
            priority: 100,
            capabilityStates: [],
            health: .degraded(reason: "runtime service connected; execution providers are not wired"),
            backgroundSessionState: .unavailable,
            metadata: [
                "serviceID": serviceID,
                "compatibility": "prism-build52",
            ]
        )
    }
}
