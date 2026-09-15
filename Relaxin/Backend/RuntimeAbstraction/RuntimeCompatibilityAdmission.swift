import Foundation

enum RuntimeCompatibilityAdmissionStatus: String, Codable, Hashable, Sendable {
    case unsupported
    case recognized
    case readyForDeviceValidation
    case verified
}

enum RuntimeCompatibilityBlocker: String, Codable, Hashable, Sendable {
    case announcementMismatch
    case baselineIntegrityMissing
    case hostContractIncomplete
    case backendImplementationMissing
    case deviceValidationRequired
}

struct RuntimeCompatibilityAdmission: Equatable, Sendable {
    let upstreamVersion: String
    let status: RuntimeCompatibilityAdmissionStatus
    let allowsExecution: Bool
    let missingBaselineIntegrity: Set<BaselineIntegrityRequirement>
    let blockers: Set<RuntimeCompatibilityBlocker>

    static func evaluate(
        announcement: RuntimeCompatibilityAnnouncement,
        hardware: HardwareSupportDescriptor,
        osVersion: String,
        availableBaselineIntegrity: Set<BaselineIntegrityRequirement>,
        hostContractReady: Bool,
        backendImplementationAvailable: Bool,
        deviceValidated: Bool
    ) -> RuntimeCompatibilityAdmission {
        guard announcement.announcesCompatibility(
            hardwareSupportID: hardware.id,
            osVersion: osVersion
        ) else {
            return RuntimeCompatibilityAdmission(
                upstreamVersion: announcement.upstreamVersion,
                status: .unsupported,
                allowsExecution: false,
                missingBaselineIntegrity: [],
                blockers: [.announcementMismatch]
            )
        }

        let missingIntegrity = hardware.requiredBaselineIntegrity
            .subtracting(availableBaselineIntegrity)
        var blockers: Set<RuntimeCompatibilityBlocker> = []
        if !missingIntegrity.isEmpty {
            blockers.insert(.baselineIntegrityMissing)
        }
        if !hostContractReady {
            blockers.insert(.hostContractIncomplete)
        }
        if !backendImplementationAvailable {
            blockers.insert(.backendImplementationMissing)
        }

        if !blockers.isEmpty {
            return RuntimeCompatibilityAdmission(
                upstreamVersion: announcement.upstreamVersion,
                status: .recognized,
                allowsExecution: false,
                missingBaselineIntegrity: missingIntegrity,
                blockers: blockers
            )
        }

        guard deviceValidated else {
            return RuntimeCompatibilityAdmission(
                upstreamVersion: announcement.upstreamVersion,
                status: .readyForDeviceValidation,
                allowsExecution: false,
                missingBaselineIntegrity: [],
                blockers: [.deviceValidationRequired]
            )
        }

        return RuntimeCompatibilityAdmission(
            upstreamVersion: announcement.upstreamVersion,
            status: .verified,
            allowsExecution: true,
            missingBaselineIntegrity: [],
            blockers: []
        )
    }
}
