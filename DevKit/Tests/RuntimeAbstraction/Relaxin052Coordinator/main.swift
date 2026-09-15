import Foundation

func requireCoordinator(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL Relaxin 0.5.2 coordinator: \(message)\n", stderr)
        exit(1)
    }
}

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
requireCoordinator(announced != nil, "A13/26.0.1 should produce a compatibility admission")
requireCoordinator(announced?.status == .recognized, "current 0.5.2 host policy must remain non-runnable without a backend implementation")
requireCoordinator(announced?.blockers.contains(.backendImplementationMissing) == true, "coordinator must expose the missing backend implementation")
requireCoordinator(announced?.allowsExecution == false, "coordinator must fail closed before device validation")

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
requireCoordinator(gap?.status == .unsupported, "A13/19.x gap must remain explicitly unsupported")

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
requireCoordinator(
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
requireCoordinator(readyForDevice?.status == .readyForDeviceValidation, "a host-ready backend candidate should stop at device validation")
requireCoordinator(readyForDevice?.allowsExecution == false, "host validation alone must never enable execution")

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
requireCoordinator(verified?.status == .verified, "device-validated policy should produce verified admission")
requireCoordinator(verified?.allowsExecution == true, "verified admission should be executable")

print("PASS Relaxin052Coordinator")
