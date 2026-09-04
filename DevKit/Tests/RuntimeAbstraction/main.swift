import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let a13 = HardwareExecutionClass.pplGFXA13
let environment = RuntimeEnvironment(
    deviceIdentifier: "iPhone12,1",
    cpuFamily: 0x4625_04D2,
    architecture: "arm64e",
    osVersion: "17.3.1",
    osBuild: "21D61",
    isSimulator: false,
    environmentSchema: 1,
    hasInstalledBootstrap: false,
    runtimeActive: false
)

let profile = RuntimeProfile(
    id: "current.stable",
    displayName: "Current Stable Profile",
    osConstraint: .versionRange(minimum: "16.5.1", maximum: "17.3.1"),
    exactBuilds: [],
    hardwareClasses: [a13],
    requiredArchitecture: "arm64e",
    requiredBackendCapabilities: [.verifyRuntime, .verifyBootstrap],
    optionalCapabilities: [.userspaceReboot],
    bootstrapGeneration: "bootstrap-1900",
    minimumEnvironmentSchema: 1,
    recoveryPolicy: .allowed,
    maturityFloor: .legacy
)

let stable = RuntimeBackendDescriptor(
    id: "legacy.relaxin",
    displayName: "Relaxin Current Engine",
    maturity: .stable,
    supportedProfileIDs: [profile.id],
    capabilities: [
        .activateRuntime, .restoreRuntime, .reuseBootstrap, .installBootstrap,
        .verifyRuntime, .verifyBootstrap, .installPackageManager, .repairPackageManager,
        .publishTrustCache, .stealthCompatibility, .structuredDiagnostics
    ],
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 1
)

let result = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [stable],
    policy: RuntimeBackendPolicy(experimentalEnabled: false, preferredBackendID: nil)
)
require(result.profileID == profile.id, "stable profile should resolve")
require(result.backendID == stable.id, "stable backend should resolve")
require(result.supportLevel == .partial, "missing optional userspace reboot should report partial")
require(result.missingCapabilities == [.userspaceReboot], "optional capability should be surfaced")

let fullStable = RuntimeBackendDescriptor(
    id: "legacy.relaxin.full",
    displayName: "Relaxin Full",
    maturity: .stable,
    supportedProfileIDs: [profile.id],
    capabilities: stable.capabilities.union([.userspaceReboot]),
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 2
)
let supported = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [stable, fullStable],
    policy: RuntimeBackendPolicy(experimentalEnabled: false, preferredBackendID: nil)
)
require(supported.backendID == fullStable.id, "higher generation stable backend should win equal candidates")
require(supported.supportLevel == .supported, "full stable backend should be supported")

let experimental = RuntimeBackendDescriptor(
    id: "experimental.runtime",
    displayName: "Experimental Runtime",
    maturity: .experimental,
    supportedProfileIDs: [profile.id],
    capabilities: fullStable.capabilities,
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 10
)
let experimentalOff = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [experimental],
    policy: RuntimeBackendPolicy(experimentalEnabled: false, preferredBackendID: nil)
)
require(experimentalOff.supportLevel == .unsupported, "experimental backend must not activate without opt-in")
require(experimentalOff.rejectedCandidates.contains { $0.reasonCode == .experimentalBackendDisabled }, "disabled experimental reason required")

let experimentalOn = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [experimental],
    policy: RuntimeBackendPolicy(experimentalEnabled: true, preferredBackendID: nil)
)
require(experimentalOn.backendID == experimental.id, "experimental backend should resolve with opt-in")
require(experimentalOn.supportLevel == .experimental, "experimental backend should report experimental")

let recoveryEnvironment = RuntimeEnvironment(
    deviceIdentifier: environment.deviceIdentifier,
    cpuFamily: environment.cpuFamily,
    architecture: environment.architecture,
    osVersion: environment.osVersion,
    osBuild: environment.osBuild,
    isSimulator: false,
    environmentSchema: 1,
    hasInstalledBootstrap: true,
    runtimeActive: false
)
let recoveryBackend = RuntimeBackendDescriptor(
    id: "recovery.only",
    displayName: "Recovery Only",
    maturity: .stable,
    supportedProfileIDs: [profile.id],
    capabilities: [.restoreRuntime, .reuseBootstrap, .verifyRuntime, .verifyBootstrap],
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 1
)
let recovery = RuntimeProfileResolver.resolve(
    environment: recoveryEnvironment,
    profiles: [profile],
    backends: [recoveryBackend],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(recovery.supportLevel == .recoveryOnly, "installed environment should allow recovery-only backend")

let missingProfile = RuntimeProfileResolver.resolve(
    environment: RuntimeEnvironment(
        deviceIdentifier: "future",
        cpuFamily: environment.cpuFamily,
        architecture: "arm64e",
        osVersion: "99.0",
        osBuild: "99A1",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false
    ),
    profiles: [profile],
    backends: [fullStable],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(missingProfile.supportLevel == .unsupported, "no matching profile must be unsupported")
require(missingProfile.rejectedCandidates.contains { $0.reasonCode.rawValue == "runtime_profile_missing" }, "no matching profile requires runtime_profile_missing summary reason")
require(missingProfile.rejectedCandidates.contains { $0.reasonCode == .profileOSMismatch }, "profile OS mismatch reason required")

let noBackend = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(noBackend.supportLevel == .unsupported, "profile without backend must be unsupported")
require(noBackend.rejectedCandidates.contains { $0.reasonCode == .runtimeBackendMissing }, "missing backend reason required")

let insufficient = RuntimeBackendDescriptor(
    id: "insufficient",
    displayName: "Insufficient",
    maturity: .stable,
    supportedProfileIDs: [profile.id],
    capabilities: [.verifyRuntime],
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 1
)
let rejected = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [insufficient],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(rejected.supportLevel == .unsupported, "missing required backend capability must reject candidate")
require(rejected.rejectedCandidates.contains { $0.reasonCode == .backendCapabilityMissing }, "capability rejection reason required")


let legacyBackend = RuntimeBackendDescriptor(
    id: "legacy.only",
    displayName: "Legacy Only",
    maturity: .legacy,
    supportedProfileIDs: [profile.id],
    capabilities: fullStable.capabilities,
    hardwareClasses: [a13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 99
)
let stableOnlyProfile = RuntimeProfile(
    id: "stable.floor",
    displayName: "Stable Floor",
    osConstraint: profile.osConstraint,
    exactBuilds: profile.exactBuilds,
    hardwareClasses: profile.hardwareClasses,
    requiredArchitecture: profile.requiredArchitecture,
    requiredBackendCapabilities: profile.requiredBackendCapabilities,
    optionalCapabilities: profile.optionalCapabilities,
    bootstrapGeneration: profile.bootstrapGeneration,
    minimumEnvironmentSchema: profile.minimumEnvironmentSchema,
    recoveryPolicy: profile.recoveryPolicy,
    maturityFloor: .stable
)
let legacyRejected = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [stableOnlyProfile],
    backends: [RuntimeBackendDescriptor(
        id: legacyBackend.id,
        displayName: legacyBackend.displayName,
        maturity: legacyBackend.maturity,
        supportedProfileIDs: [stableOnlyProfile.id],
        capabilities: legacyBackend.capabilities,
        hardwareClasses: legacyBackend.hardwareClasses,
        minimumEnvironmentSchema: legacyBackend.minimumEnvironmentSchema,
        backendGeneration: legacyBackend.backendGeneration
    )],
    policy: .recommended
)
require(legacyRejected.supportLevel == .unsupported, "legacy backend must be rejected when profile does not permit legacy maturity")
require(legacyRejected.rejectedCandidates.contains { $0.reasonCode.rawValue == "backend_maturity_incompatible" }, "legacy maturity rejection reason required")

let repeated = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [stable, fullStable, experimental],
    policy: .init(experimentalEnabled: true, preferredBackendID: nil)
)
let repeatedAgain = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [stable, fullStable, experimental],
    policy: .init(experimentalEnabled: true, preferredBackendID: nil)
)
require(repeated == repeatedAgain, "resolver must be deterministic")

require(RuntimeOperationRequirements.freshInstall(packageManagerSelected: true).contains(.activateRuntime), "fresh install requires activation")
require(RuntimeOperationRequirements.restore.contains(.restoreRuntime), "restore requires restore capability")
require(!RuntimeOperationRequirements.restore.contains(.activateRuntime), "restore must not require fresh activation")
require(RuntimeOperationRequirements.stealth == [.stealthCompatibility], "stealth requirement must remain capability-specific")

print("PASS RuntimeAbstraction")
