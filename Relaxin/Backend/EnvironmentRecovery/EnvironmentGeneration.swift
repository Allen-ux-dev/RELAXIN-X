import Foundation

struct EnvironmentFingerprint: Codable, Equatable, Hashable, Sendable {
    let hardwareIdentifier: String
    let osVersion: String
    let osBuild: String

    static let unknown = EnvironmentFingerprint(
        hardwareIdentifier: "unknown",
        osVersion: "unknown",
        osBuild: "unknown"
    )
}

struct EnvironmentGeneration: Codable, Equatable, Hashable, Sendable {
    let relaxinBuild: String
    let bootstrapGeneration: String
    let baseBinGeneration: String
    let environmentSchema: Int
    let profileRulesVersion: Int
    let runtimeAbstractionSchema: Int
    let upstreamBaselineID: String
    let runtimeBackendGeneration: Int
    let runtimeResolutionGeneration: Int

    // These values identify user-space state whose verification may be cached.
    // Bump only when the corresponding on-device contract changes.
    static let currentBootstrapGeneration = "1900"
    static let currentBaseBinGeneration = "public-snapshot-f44e0acf-fix12"
    static let currentEnvironmentSchema = 1
    static let currentProfileRulesVersion = 2
    static let currentRuntimeAbstractionSchema = 2
    static let currentUpstreamBaselineID = "relaxin.upstream.v0.5.0.20260826"
    static let currentRuntimeBackendGeneration = 2
    static let currentRuntimeResolutionGeneration = 2
    static let legacyUnknownBaselineID = "legacy.unknown"

    init(
        relaxinBuild: String,
        bootstrapGeneration: String,
        baseBinGeneration: String,
        environmentSchema: Int,
        profileRulesVersion: Int,
        runtimeAbstractionSchema: Int = currentRuntimeAbstractionSchema,
        upstreamBaselineID: String = legacyUnknownBaselineID,
        runtimeBackendGeneration: Int = 1,
        runtimeResolutionGeneration: Int = 1
    ) {
        self.relaxinBuild = relaxinBuild
        self.bootstrapGeneration = bootstrapGeneration
        self.baseBinGeneration = baseBinGeneration
        self.environmentSchema = environmentSchema
        self.profileRulesVersion = profileRulesVersion
        self.runtimeAbstractionSchema = runtimeAbstractionSchema
        self.upstreamBaselineID = upstreamBaselineID
        self.runtimeBackendGeneration = runtimeBackendGeneration
        self.runtimeResolutionGeneration = runtimeResolutionGeneration
    }

    private enum CodingKeys: String, CodingKey {
        case relaxinBuild
        case bootstrapGeneration
        case baseBinGeneration
        case environmentSchema
        case profileRulesVersion
        case runtimeAbstractionSchema
        case upstreamBaselineID
        case runtimeBackendGeneration
        case runtimeResolutionGeneration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relaxinBuild = try container.decode(String.self, forKey: .relaxinBuild)
        bootstrapGeneration = try container.decode(String.self, forKey: .bootstrapGeneration)
        baseBinGeneration = try container.decode(String.self, forKey: .baseBinGeneration)
        environmentSchema = try container.decode(Int.self, forKey: .environmentSchema)
        profileRulesVersion = try container.decode(Int.self, forKey: .profileRulesVersion)
        runtimeAbstractionSchema = try container.decodeIfPresent(Int.self, forKey: .runtimeAbstractionSchema) ?? 1
        upstreamBaselineID = try container.decodeIfPresent(String.self, forKey: .upstreamBaselineID)
            ?? Self.legacyUnknownBaselineID
        runtimeBackendGeneration = try container.decodeIfPresent(Int.self, forKey: .runtimeBackendGeneration) ?? 1
        runtimeResolutionGeneration = try container.decodeIfPresent(Int.self, forKey: .runtimeResolutionGeneration) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relaxinBuild, forKey: .relaxinBuild)
        try container.encode(bootstrapGeneration, forKey: .bootstrapGeneration)
        try container.encode(baseBinGeneration, forKey: .baseBinGeneration)
        try container.encode(environmentSchema, forKey: .environmentSchema)
        try container.encode(profileRulesVersion, forKey: .profileRulesVersion)
        try container.encode(runtimeAbstractionSchema, forKey: .runtimeAbstractionSchema)
        try container.encode(upstreamBaselineID, forKey: .upstreamBaselineID)
        try container.encode(runtimeBackendGeneration, forKey: .runtimeBackendGeneration)
        try container.encode(runtimeResolutionGeneration, forKey: .runtimeResolutionGeneration)
    }

    static let baseline = EnvironmentGeneration(
        relaxinBuild: "unknown",
        bootstrapGeneration: currentBootstrapGeneration,
        baseBinGeneration: currentBaseBinGeneration,
        environmentSchema: currentEnvironmentSchema,
        profileRulesVersion: currentProfileRulesVersion,
        runtimeAbstractionSchema: currentRuntimeAbstractionSchema,
        upstreamBaselineID: currentUpstreamBaselineID,
        runtimeBackendGeneration: currentRuntimeBackendGeneration,
        runtimeResolutionGeneration: currentRuntimeResolutionGeneration
    )

    static func current(relaxinBuild: String) -> EnvironmentGeneration {
        EnvironmentGeneration(
            relaxinBuild: relaxinBuild,
            bootstrapGeneration: currentBootstrapGeneration,
            baseBinGeneration: currentBaseBinGeneration,
            environmentSchema: currentEnvironmentSchema,
            profileRulesVersion: currentProfileRulesVersion,
            runtimeAbstractionSchema: currentRuntimeAbstractionSchema,
            upstreamBaselineID: currentUpstreamBaselineID,
            runtimeBackendGeneration: currentRuntimeBackendGeneration,
            runtimeResolutionGeneration: currentRuntimeResolutionGeneration
        )
    }
}
