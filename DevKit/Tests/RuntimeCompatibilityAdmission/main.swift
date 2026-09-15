import Foundation

func requireAdmission(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL RuntimeCompatibilityAdmission: \(message)\n", stderr)
        exit(1)
    }
}

let announcement = RuntimeProfileRegistry.relaxin052PublicBetaAnnouncement
let a13 = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.pplGFXA13.rawValue)!
let a16 = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.gfxA16.rawValue)!
let a17 = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.sptmGFXA17.rawValue)!

let a13NoEvidence = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [],
    hostContractReady: true,
    backendImplementationAvailable: false,
    deviceValidated: false
)
requireAdmission(a13NoEvidence.status == .recognized, "announced A13/26.0.1 should be recognized")
requireAdmission(!a13NoEvidence.allowsExecution, "recognized compatibility must never execute")
requireAdmission(
    a13NoEvidence.missingBaselineIntegrity == [.kernelProfilePresent, .kernelcacheDigestPresent],
    "A13 should report the exact static baseline evidence still missing"
)

let a13StaticReady = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: false,
    deviceValidated: false
)
requireAdmission(a13StaticReady.status == .recognized, "static metadata alone must not imply runnable support")
requireAdmission(!a13StaticReady.allowsExecution, "missing backend implementation must block execution")
requireAdmission(a13StaticReady.blockers.contains(.backendImplementationMissing), "backend blocker must be explicit")

let a13ReadyForDevice = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: false
)
requireAdmission(a13ReadyForDevice.status == .readyForDeviceValidation, "host-ready backend candidate should require device validation")
requireAdmission(!a13ReadyForDevice.allowsExecution, "device validation boundary must remain fail-closed")
requireAdmission(a13ReadyForDevice.blockers == [.deviceValidationRequired], "device validation should be the only blocker")

let a13Verified = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
requireAdmission(a13Verified.status == .verified, "device-validated candidate should become verified")
requireAdmission(a13Verified.allowsExecution, "only verified compatibility may execute")
requireAdmission(a13Verified.blockers.isEmpty, "verified compatibility must have no blockers")

let gap = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "19.0",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
requireAdmission(gap.status == .unsupported, "A13 gap versions must remain unsupported")
requireAdmission(!gap.allowsExecution, "unsupported gap versions must never execute")

let a16TooNew = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a16,
    osVersion: "18.0",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
requireAdmission(a16TooNew.status == .unsupported, "A16 must not inherit A12/A13 extended support")

let a17MissingSPTM = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a17,
    osVersion: "17.3.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: false
)
requireAdmission(a17MissingSPTM.status == .recognized, "A17 should remain recognized while SPTM evidence is incomplete")
requireAdmission(
    a17MissingSPTM.missingBaselineIntegrity == [.sptmDigestPresent, .txmDigestPresent],
    "A17 should preserve the stricter SPTM/TXM evidence gate"
)

let hostNotReady = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13,
    osVersion: "18.7.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: false,
    backendImplementationAvailable: true,
    deviceValidated: true
)
requireAdmission(hostNotReady.status == .recognized, "host contract must be ready before compatibility can advance")
requireAdmission(hostNotReady.blockers.contains(.hostContractIncomplete), "host contract blocker must be explicit")
requireAdmission(!hostNotReady.allowsExecution, "host-incomplete candidates must fail closed")

print("PASS RuntimeCompatibilityAdmission")
