import Foundation

struct RuntimeCompatibilityValidationRecord: Equatable, Hashable, Sendable {
    let upstreamVersion: String
    let hostContractReady: Bool
    let backendImplementationAvailable: Bool
    let deviceValidated: Bool
}

enum RuntimeCompatibilityValidationRegistry {
    // The host-side 0.5.2 routing/validation contract is implemented, but the
    // extended-system backend has not been independently verified on-device.
    // Keep execution blocked until both implementation and device validation
    // evidence are explicitly promoted here.
    static let relaxin052 = RuntimeCompatibilityValidationRecord(
        upstreamVersion: "0.5.2",
        hostContractReady: true,
        backendImplementationAvailable: false,
        deviceValidated: false
    )
}

enum RuntimeCompatibilityCoordinator {
    static func evaluate(
        environment: RuntimeEnvironment,
        announcement: RuntimeCompatibilityAnnouncement = RuntimeProfileRegistry.relaxin052PublicBetaAnnouncement,
        validation: RuntimeCompatibilityValidationRecord = RuntimeCompatibilityValidationRegistry.relaxin052
    ) -> RuntimeCompatibilityAdmission? {
        guard validation.upstreamVersion == announcement.upstreamVersion,
              let hardware = environment.hardwareSupportDescriptor
        else { return nil }

        return RuntimeCompatibilityAdmission.evaluate(
            announcement: announcement,
            hardware: hardware,
            osVersion: environment.osVersion,
            availableBaselineIntegrity: environment.availableBaselineIntegrity,
            hostContractReady: validation.hostContractReady,
            backendImplementationAvailable: validation.backendImplementationAvailable,
            deviceValidated: validation.deviceValidated
        )
    }
}
