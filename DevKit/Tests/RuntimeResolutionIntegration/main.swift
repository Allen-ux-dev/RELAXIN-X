import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func resolution(
    support: RuntimeSupportLevel,
    capabilities: Set<RuntimeCapability>
) -> RuntimeResolution {
    RuntimeResolution(
        environmentIdentity: "device|17.3.1|21D61|ppl-gfx-a13|arm64e|1",
        profileID: "profile",
        profileDisplayName: "Profile",
        backendID: "backend",
        backendDisplayName: "Backend",
        backendMaturity: .stable,
        backendGeneration: 1,
        supportLevel: support,
        capabilities: capabilities,
        missingCapabilities: [],
        warnings: [],
        rejectedCandidates: [],
        resolutionGeneration: 1
    )
}

func snapshot(
    runtimeActive: Bool,
    bootstrap: BootstrapEvidence,
    runtimeResolution: RuntimeResolution
) -> EnvironmentSnapshot {
    EnvironmentSnapshot(
        target: TargetEvidence(supported: true, reason: nil),
        runtime: RuntimeEvidence(
            active: runtimeActive,
            rootHideReportedJailbroken: runtimeActive,
            processRuntimeActive: runtimeActive,
            processIsPlatform: runtimeActive
        ),
        bootstrap: bootstrap,
        storage: .sufficient,
        packageManagers: PackageManagerEvidence(sileo: .healthy, zebra: .notInstalled),
        conflicts: [],
        historicalHint: .none,
        fingerprint: .unknown,
        generation: .baseline,
        runtimeResolution: runtimeResolution,
        inspectedAt: Date()
    )
}

let fullCaps: Set<RuntimeCapability> = [
    .activateRuntime, .installBootstrap, .restoreRuntime, .reuseBootstrap,
    .verifyRuntime, .verifyBootstrap, .installPackageManager,
    .repairPackageManager, .stealthCompatibility
]
let clean = snapshot(runtimeActive: false, bootstrap: .absent, runtimeResolution: resolution(support: .supported, capabilities: fullCaps))
let freshGate = CompatibilityGate.evaluate(clean, requirements: RuntimeOperationRequirements.freshInstall(packageManagerSelected: true))
require(!freshGate.disposition.isUnsupported, "full capability fresh install must be admitted")

let recoveryCaps: Set<RuntimeCapability> = [.restoreRuntime, .reuseBootstrap, .verifyRuntime, .verifyBootstrap]
let recovery = snapshot(runtimeActive: false, bootstrap: .validRelaxin(identity: "root"), runtimeResolution: resolution(support: .recoveryOnly, capabilities: recoveryCaps))
let restoreGate = CompatibilityGate.evaluate(recovery, requirements: RuntimeOperationRequirements.restore)
require(!restoreGate.disposition.isUnsupported, "recovery-only backend must admit restore")
let recoveryFresh = CompatibilityGate.evaluate(recovery, requirements: RuntimeOperationRequirements.freshInstall(packageManagerSelected: false))
require(recoveryFresh.disposition.isUnsupported, "recovery-only backend must reject fresh activation")

let activeRepair = snapshot(runtimeActive: true, bootstrap: .validRelaxin(identity: "root"), runtimeResolution: resolution(support: .partial, capabilities: [.repairPackageManager, .verifyRuntime, .verifyBootstrap]))
let repairGate = CompatibilityGate.evaluate(activeRepair, requirements: RuntimeOperationRequirements.repair(packageManager: true))
require(!repairGate.disposition.isUnsupported, "repair must not require unrelated capabilities")
let stealthGate = CompatibilityGate.evaluate(activeRepair, requirements: RuntimeOperationRequirements.stealth)
require(stealthGate.disposition.isUnsupported, "Stealth must be unavailable when backend lacks stealth capability")

let unsupported = snapshot(runtimeActive: false, bootstrap: .absent, runtimeResolution: resolution(support: .unsupported, capabilities: []))
require(CompatibilityGate.evaluate(unsupported).disposition.isUnsupported, "unresolved runtime must be unsupported")

print("PASS RuntimeResolutionState")
