import Foundation

enum StaleStateInvalidator {
    struct Decision: Equatable, Sendable {
        let invalidateCheckpoint: Bool
        let invalidateHealthVerification: Bool
        let invalidateCachedTargetMetadata: Bool
        let invalidateKernelMetadata: Bool
        let preserveExplicitProfilePreferences: Bool
        let deleteEnvironment: Bool
        let reasons: [String]
    }

    static func compare(
        previousGeneration: EnvironmentGeneration,
        currentGeneration: EnvironmentGeneration,
        previousFingerprint: EnvironmentFingerprint,
        currentFingerprint: EnvironmentFingerprint
    ) -> Decision {
        let generationChanged = previousGeneration != currentGeneration
        let baselineChanged = previousGeneration.upstreamBaselineID != currentGeneration.upstreamBaselineID
        let hardwareChanged = previousFingerprint.hardwareIdentifier
            != currentFingerprint.hardwareIdentifier
        let osVersionChanged = previousFingerprint.osVersion != currentFingerprint.osVersion
        let osBuildChanged = previousFingerprint.osBuild != currentFingerprint.osBuild
        let fingerprintChanged = hardwareChanged || osVersionChanged || osBuildChanged

        var reasons: [String] = []
        if previousGeneration.relaxinBuild != currentGeneration.relaxinBuild {
            reasons.append("relaxin_build_changed")
        }
        if baselineChanged {
            reasons.append("upstream_baseline_changed")
        }
        if previousGeneration.bootstrapGeneration != currentGeneration.bootstrapGeneration {
            reasons.append("bootstrap_generation_changed")
        }
        if previousGeneration.baseBinGeneration != currentGeneration.baseBinGeneration {
            reasons.append("basebin_generation_changed")
        }
        if previousGeneration.environmentSchema != currentGeneration.environmentSchema {
            reasons.append("environment_schema_changed")
        }
        if previousGeneration.profileRulesVersion != currentGeneration.profileRulesVersion {
            reasons.append("profile_rules_changed")
        }
        if previousGeneration.runtimeAbstractionSchema != currentGeneration.runtimeAbstractionSchema {
            reasons.append("runtime_abstraction_schema_changed")
        }
        if previousGeneration.runtimeBackendGeneration != currentGeneration.runtimeBackendGeneration {
            reasons.append("runtime_backend_generation_changed")
        }
        if previousGeneration.runtimeResolutionGeneration != currentGeneration.runtimeResolutionGeneration {
            reasons.append("runtime_resolution_generation_changed")
        }
        if hardwareChanged { reasons.append("hardware_identifier_changed") }
        if osVersionChanged { reasons.append("os_version_changed") }
        if osBuildChanged { reasons.append("os_build_changed") }

        return Decision(
            invalidateCheckpoint: generationChanged || fingerprintChanged,
            invalidateHealthVerification: generationChanged || fingerprintChanged,
            invalidateCachedTargetMetadata: fingerprintChanged,
            invalidateKernelMetadata: baselineChanged || fingerprintChanged,
            preserveExplicitProfilePreferences: true,
            deleteEnvironment: false,
            reasons: reasons
        )
    }
}
