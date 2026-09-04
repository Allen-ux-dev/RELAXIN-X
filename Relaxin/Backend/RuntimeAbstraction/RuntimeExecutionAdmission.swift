import Foundation

enum RuntimeExecutionAdmissionResult: Equatable, Sendable {
    case admitted
    case resolutionUnavailable
    case resolutionChanged([String])
    case missingCapabilities([RuntimeCapability])
}

enum RuntimeExecutionAdmission {
    static func validate(
        selectedIdentity: RuntimeResolutionIdentity,
        freshResolution: RuntimeResolution,
        requirements: Set<RuntimeCapability>
    ) -> RuntimeExecutionAdmissionResult {
        guard let freshIdentity = freshResolution.checkpointIdentity else {
            return .resolutionUnavailable
        }
        let mismatch = selectedIdentity.mismatchReasons(comparedWith: freshIdentity)
        guard mismatch.isEmpty else {
            return .resolutionChanged(mismatch)
        }
        let missing = requirements.subtracting(freshResolution.capabilities)
            .sorted { $0.rawValue < $1.rawValue }
        guard missing.isEmpty else {
            return .missingCapabilities(missing)
        }
        return .admitted
    }
}
