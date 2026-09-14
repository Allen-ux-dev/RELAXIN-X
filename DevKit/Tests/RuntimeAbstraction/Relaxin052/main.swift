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

print("PASS Relaxin052Compatibility")
