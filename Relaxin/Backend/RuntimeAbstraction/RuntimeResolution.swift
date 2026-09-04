import Foundation

enum RuntimeResolutionRejectionCode: String, Codable, Hashable, Sendable {
    case simulatorUnsupported = "simulator_unsupported"
    case identityMissing = "runtime_identity_missing"
    case profileOSMismatch = "profile_os_mismatch"
    case profileBuildMismatch = "profile_build_mismatch"
    case hardwareClassMismatch = "hardware_class_mismatch"
    case architectureMismatch = "architecture_mismatch"
    case environmentSchemaTooOld = "environment_schema_too_old"
    case runtimeProfileMissing = "runtime_profile_missing"
    case runtimeBackendMissing = "runtime_backend_missing"
    case backendMaturityIncompatible = "backend_maturity_incompatible"
    case backendProfileMismatch = "backend_profile_mismatch"
    case backendHardwareMismatch = "backend_hardware_mismatch"
    case backendCapabilityMissing = "backend_capability_missing"
    case experimentalBackendDisabled = "experimental_backend_disabled"
    case backendGenerationIncompatible = "backend_generation_incompatible"
    case baselineMissing = "baseline_missing"
    case baselineSchemaUnsupported = "baseline_schema_unsupported"
    case baselineResourceMismatch = "baseline_resource_mismatch"
    case hardwareRecognizedButUnsupported = "hardware_recognized_but_unsupported"
    case hardwareExperimentalDisabled = "hardware_experimental_disabled"
    case requiredBaselineMetadataMissing = "required_baseline_metadata_missing"
    case backendGenerationTooOld = "backend_generation_too_old"
}

struct RuntimeRejectedCandidate: Equatable, Hashable, Sendable {
    let profileID: String?
    let backendID: String?
    let reasonCode: RuntimeResolutionRejectionCode
    let detail: String
}

struct RuntimeResolution: Equatable, Sendable {
    let environmentIdentity: String
    let profileID: String?
    let profileDisplayName: String?
    let baselineID: String?
    let backendID: String?
    let backendDisplayName: String?
    let backendMaturity: BackendMaturity?
    let backendGeneration: Int?
    let supportLevel: RuntimeSupportLevel
    let capabilities: Set<RuntimeCapability>
    let missingCapabilities: Set<RuntimeCapability>
    let warnings: [String]
    let rejectedCandidates: [RuntimeRejectedCandidate]
    let resolutionGeneration: Int

    init(
        environmentIdentity: String,
        profileID: String?,
        profileDisplayName: String?,
        baselineID: String? = nil,
        backendID: String?,
        backendDisplayName: String?,
        backendMaturity: BackendMaturity?,
        backendGeneration: Int?,
        supportLevel: RuntimeSupportLevel,
        capabilities: Set<RuntimeCapability>,
        missingCapabilities: Set<RuntimeCapability>,
        warnings: [String],
        rejectedCandidates: [RuntimeRejectedCandidate],
        resolutionGeneration: Int
    ) {
        self.environmentIdentity = environmentIdentity
        self.profileID = profileID
        self.profileDisplayName = profileDisplayName
        self.baselineID = baselineID
        self.backendID = backendID
        self.backendDisplayName = backendDisplayName
        self.backendMaturity = backendMaturity
        self.backendGeneration = backendGeneration
        self.supportLevel = supportLevel
        self.capabilities = capabilities
        self.missingCapabilities = missingCapabilities
        self.warnings = warnings
        self.rejectedCandidates = rejectedCandidates
        self.resolutionGeneration = resolutionGeneration
    }

    var isResolved: Bool { profileID != nil && backendID != nil }

    func supports(_ requirements: Set<RuntimeCapability>) -> Bool {
        requirements.isSubset(of: capabilities)
    }
}

extension RuntimeResolution {
    var checkpointIdentity: RuntimeResolutionIdentity? {
        guard let profileID, let backendID, let backendGeneration else { return nil }
        return RuntimeResolutionIdentity(
            profileID: profileID,
            baselineID: baselineID,
            backendID: backendID,
            backendGeneration: backendGeneration,
            resolutionGeneration: resolutionGeneration
        )
    }
}
