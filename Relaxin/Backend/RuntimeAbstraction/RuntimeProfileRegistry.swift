import Foundation

struct RuntimeCompatibilityBand: Equatable, Hashable, Sendable {
    let hardwareSupportIDs: Set<String>
    let osConstraint: RuntimeOSConstraint

    func matches(hardwareSupportID: String, osVersion: String) -> Bool {
        hardwareSupportIDs.contains(hardwareSupportID) && osConstraint.matches(osVersion)
    }
}

enum RuntimeCompatibilityEvidence: String, Codable, Hashable, Sendable {
    case publicAnnouncement
}

struct RuntimeCompatibilityAnnouncement: Equatable, Hashable, Sendable {
    let upstreamVersion: String
    let releaseChannel: String
    let evidence: RuntimeCompatibilityEvidence
    let bands: [RuntimeCompatibilityBand]
    let reportedFeatures: Set<String>
    let executableBackendVerified: Bool

    func announcesCompatibility(hardwareSupportID: String, osVersion: String) -> Bool {
        bands.contains { $0.matches(hardwareSupportID: hardwareSupportID, osVersion: osVersion) }
    }
}

enum RuntimeProfileRegistry {
    static let legacyPublicSnapshotID = "relaxin.public-snapshot.f44e0acf"
    static let currentPublicSnapshotID = legacyPublicSnapshotID
    static let productionProfileID = "relaxin.upstream.v0.5.0.profile"

    // Publicly announced 0.5.2 compatibility is kept separate from the verified
    // production runtime profile. It must not become executable routing until a
    // matching baseline/backend is independently verified and registered.
    static let relaxin052PublicBetaAnnouncement = RuntimeCompatibilityAnnouncement(
        upstreamVersion: "0.5.2",
        releaseChannel: "public-beta",
        evidence: .publicAnnouncement,
        bands: [
            RuntimeCompatibilityBand(
                hardwareSupportIDs: [
                    HardwareExecutionClass.pplDMAA12.rawValue,
                    HardwareExecutionClass.pplGFXA13.rawValue,
                ],
                osConstraint: .versionRanges([
                    RuntimeVersionRange(minimum: "16.5.1", maximum: "18.7.1"),
                    RuntimeVersionRange(minimum: "26.0", maximum: "26.0.1"),
                ])
            ),
            RuntimeCompatibilityBand(
                hardwareSupportIDs: [
                    HardwareExecutionClass.pplGFXA14M1.rawValue,
                    HardwareExecutionClass.gfxA15M2.rawValue,
                    HardwareExecutionClass.gfxA16.rawValue,
                ],
                osConstraint: .versionRange(minimum: "16.5.1", maximum: "17.3.1")
            ),
            RuntimeCompatibilityBand(
                hardwareSupportIDs: [HardwareExecutionClass.sptmGFXA17.rawValue],
                osConstraint: .versionRange(minimum: "17.0", maximum: "17.3.1")
            ),
        ],
        reportedFeatures: [
            "improved-jit-handling",
            "improved-roothide-isolation",
            "improved-trollstore-cleanup",
            "stability-fixes",
        ],
        executableBackendVerified: false
    )

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
