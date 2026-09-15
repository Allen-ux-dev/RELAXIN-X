import Foundation

func require052(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL Relaxin 0.5.2 compatibility: \(message)\n", stderr)
        exit(1)
    }
}

let discontinuous = RuntimeOSConstraint.versionRanges([
    RuntimeVersionRange(minimum: "16.5.1", maximum: "18.7.1"),
    RuntimeVersionRange(minimum: "26.0", maximum: "26.0.1"),
])
require052(discontinuous.matches("16.5.1"), "lower A12/A13 band boundary should match")
require052(discontinuous.matches("18.7.1"), "upper A12/A13 legacy band boundary should match")
require052(!discontinuous.matches("19.0"), "gap versions must not be treated as supported")
require052(!discontinuous.matches("25.9"), "pre-26 gap versions must not be treated as supported")
require052(discontinuous.matches("26.0"), "26.0 should match the announced second band")
require052(discontinuous.matches("26.0.1"), "26.0.1 should match the announced second band")
require052(!discontinuous.matches("26.0.2"), "versions beyond the announced second band must not match")

let announcement = RuntimeProfileRegistry.relaxin052PublicBetaAnnouncement
require052(announcement.upstreamVersion == "0.5.2", "upstream version metadata should remain explicit")
require052(announcement.releaseChannel == "public-beta", "release channel should remain public-beta")
require052(announcement.evidence == .publicAnnouncement, "0.5.2 metadata must remain announcement-scoped")
require052(!announcement.executableBackendVerified, "announcement metadata must not activate an unverified backend")

require052(
    announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.pplDMAA12.rawValue,
        osVersion: "18.7.1"
    ),
    "A12 should include the announced 18.7.1 boundary"
)
require052(
    announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.pplGFXA13.rawValue,
        osVersion: "26.0.1"
    ),
    "A13 should include the announced 26.0.1 boundary"
)
require052(
    !announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.pplGFXA13.rawValue,
        osVersion: "19.0"
    ),
    "A13 must not turn the discontinuous announcement into a continuous range"
)
require052(
    announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.pplGFXA14M1.rawValue,
        osVersion: "17.3.1"
    ),
    "A14/M1 should include 17.3.1"
)
require052(
    !announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.pplGFXA14M1.rawValue,
        osVersion: "17.4"
    ),
    "A14/M1 must not inherit the A12/A13 extended range"
)
require052(
    announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.gfxA15M2.rawValue,
        osVersion: "17.3.1"
    ),
    "A15/M2 should include 17.3.1"
)
require052(
    announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.sptmGFXA17.rawValue,
        osVersion: "17.0"
    ),
    "A17 should begin at its real iOS 17 floor"
)
require052(
    !announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.sptmGFXA17.rawValue,
        osVersion: "16.5.1"
    ),
    "A17 must not advertise an impossible pre-launch iOS 16 combination"
)
require052(
    !announcement.announcesCompatibility(
        hardwareSupportID: HardwareExecutionClass.sptmGFXA17.rawValue,
        osVersion: "17.4"
    ),
    "A17 must remain capped at 17.3.1 in the announcement contract"
)

require052(
    announcement.reportedFeatures == [
        "improved-jit-handling",
        "improved-roothide-isolation",
        "improved-trollstore-cleanup",
        "stability-fixes",
    ],
    "reported 0.5.2 feature metadata should stay deterministic"
)

require052(
    RuntimeProfileRegistry.productionProfileID == "relaxin.upstream.v0.5.0.profile",
    "verified production routing must remain pinned to the existing 0.5.0 baseline"
)

let a13Descriptor = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.pplGFXA13.rawValue)!
let a16Descriptor = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.gfxA16.rawValue)!
let a17Descriptor = HardwareSupportRegistry.descriptor(id: HardwareExecutionClass.sptmGFXA17.rawValue)!

let a13NoEvidence = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13Descriptor,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [],
    hostContractReady: true,
    backendImplementationAvailable: false,
    deviceValidated: false
)
require052(a13NoEvidence.status == .recognized, "announced A13/26.0.1 should be recognized")
require052(!a13NoEvidence.allowsExecution, "recognized compatibility must never execute")
require052(
    a13NoEvidence.missingBaselineIntegrity == [.kernelProfilePresent, .kernelcacheDigestPresent],
    "A13 should expose missing baseline evidence instead of pretending to support execution"
)

let a13StaticReady = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13Descriptor,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: false,
    deviceValidated: false
)
require052(a13StaticReady.status == .recognized, "static metadata alone must not imply runnable support")
require052(a13StaticReady.blockers.contains(.backendImplementationMissing), "backend blocker must remain explicit")
require052(!a13StaticReady.allowsExecution, "missing backend implementation must fail closed")

let a13ReadyForDevice = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13Descriptor,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: false
)
require052(a13ReadyForDevice.status == .readyForDeviceValidation, "host-ready backend candidates should stop at the device-validation boundary")
require052(a13ReadyForDevice.blockers == [.deviceValidationRequired], "device validation should be the only blocker once host prerequisites are complete")
require052(!a13ReadyForDevice.allowsExecution, "device-validation candidates must still fail closed")

let a13Verified = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13Descriptor,
    osVersion: "26.0.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
require052(a13Verified.status == .verified, "device-validated candidates should become verified")
require052(a13Verified.allowsExecution, "verified compatibility is the only admission state that may execute")

let gapAdmission = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a13Descriptor,
    osVersion: "19.0",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
require052(gapAdmission.status == .unsupported, "A13 gap versions must remain unsupported")
require052(!gapAdmission.allowsExecution, "gap versions must never execute")

let a16TooNew = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a16Descriptor,
    osVersion: "18.0",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: true
)
require052(a16TooNew.status == .unsupported, "A16 must not inherit the A12/A13 extended range")

let a17MissingSPTM = RuntimeCompatibilityAdmission.evaluate(
    announcement: announcement,
    hardware: a17Descriptor,
    osVersion: "17.3.1",
    availableBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent],
    hostContractReady: true,
    backendImplementationAvailable: true,
    deviceValidated: false
)
require052(a17MissingSPTM.status == .recognized, "A17 should remain recognized while SPTM evidence is incomplete")
require052(
    a17MissingSPTM.missingBaselineIntegrity == [.sptmDigestPresent, .txmDigestPresent],
    "A17 should preserve its stricter SPTM/TXM evidence gate"
)

print("PASS Relaxin052Compatibility")
