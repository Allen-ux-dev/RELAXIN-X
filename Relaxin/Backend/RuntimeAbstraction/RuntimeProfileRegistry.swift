import Foundation

enum RuntimeProfileRegistry {
    static let legacyPublicSnapshotID = "relaxin.public-snapshot.f44e0acf"
    static let currentPublicSnapshotID = legacyPublicSnapshotID
    static let productionProfileID = "relaxin.upstream.v0.5.0.profile"

    static let production: [RuntimeProfile] = [
        RuntimeProfile(
            id: productionProfileID,
            displayName: "RELAXIN-X Upstream 0.5.0 Baseline",
            osConstraint: .versionRange(minimum: "16.5.1", maximum: "17.3.1"),
            exactBuilds: UpstreamBaselineRegistry.production.supportedBuilds,
            hardwareClasses: Set(HardwareExecutionClass.allCases),
            requiredArchitecture: "arm64e",
            requiredBackendCapabilities: [
                .verifyRuntime,
                .verifyBootstrap,
                .baselineIntegrityValidation,
                .hardwareRegistryV2,
            ],
            optionalCapabilities: [],
            bootstrapGeneration: "1900",
            minimumEnvironmentSchema: 1,
            recoveryPolicy: .allowed,
            maturityFloor: .stable,
            baselineID: UpstreamBaselineRegistry.production.id,
            hardwareSupportIDs: UpstreamBaselineRegistry.production.hardwareSupportSet,
            minimumBackendGeneration: 2,
            requiredBaselineIntegrity: []
        ),
    ]
}
