import Foundation

func runRelaxin052CoordinatorTests() {
    let a13Environment = RuntimeEnvironment(
        deviceIdentifier: "iPhone12,1",
        cpuFamily: 0x4625_04D2,
        architecture: "arm64e",
        osVersion: "26.0.1",
        osBuild: "23A355",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false,
        upstreamBaselineID: UpstreamBaselineRegistry.production.id,
        availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    )

    let announced = RuntimeCompatibilityCoordinator.evaluate(environment: a13Environment)
    require052(announced != nil, "A13/26.0.1 should produce a compatibility admission")
    require052(announced?.status == .recognized, "current 0.5.2 host policy must remain non-runnable without a backend implementation")
    require052(announced?.blockers.contains(.backendImplementationMissing) == true, "coordinator must expose the missing backend implementation")
    require052(announced?.allowsExecution == false, "coordinator must fail closed before device validation")

    let gapEnvironment = RuntimeEnvironment(
        deviceIdentifier: "iPhone12,1",
        cpuFamily: 0x4625_04D2,
        architecture: "arm64e",
        osVersion: "19.0",
        osBuild: "22A1",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false,
        upstreamBaselineID: UpstreamBaselineRegistry.production.id,
        availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    )
    let gap = RuntimeCompatibilityCoordinator.evaluate(environment: gapEnvironment)
    require052(gap?.status == .unsupported, "A13/19.x gap must remain explicitly unsupported")

    let unknownHardware = RuntimeEnvironment(
        deviceIdentifier: "UnknownDevice,1",
        cpuFamily: 0xFFFF_FFFF,
        architecture: "arm64e",
        osVersion: "26.0.1",
        osBuild: "23A355",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false,
        upstreamBaselineID: UpstreamBaselineRegistry.production.id,
        availableBaselineIntegrity: []
    )
    require052(
        RuntimeCompatibilityCoordinator.evaluate(environment: unknownHardware) == nil,
        "unknown hardware must not be guessed into a 0.5.2 compatibility band"
    )

    let hostReadyPolicy = RuntimeCompatibilityValidationRecord(
        upstreamVersion: "0.5.2",
        hostContractReady: true,
        backendImplementationAvailable: true,
        deviceValidated: false
    )
    let readyForDevice = RuntimeCompatibilityCoordinator.evaluate(
        environment: a13Environment,
        validation: hostReadyPolicy
    )
    require052(readyForDevice?.status == .readyForDeviceValidation, "a host-ready backend candidate should stop at device validation")
    require052(readyForDevice?.allowsExecution == false, "host validation alone must never enable execution")

    let verifiedPolicy = RuntimeCompatibilityValidationRecord(
        upstreamVersion: "0.5.2",
        hostContractReady: true,
        backendImplementationAvailable: true,
        deviceValidated: true
    )
    let verified = RuntimeCompatibilityCoordinator.evaluate(
        environment: a13Environment,
        validation: verifiedPolicy
    )
    require052(verified?.status == .verified, "device-validated policy should produce verified admission")
    require052(verified?.allowsExecution == true, "verified admission should be executable")
}
