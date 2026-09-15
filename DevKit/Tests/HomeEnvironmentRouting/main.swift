import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

expect(
    EnvironmentPrimaryAction.resolve(state: .clean) == .startJailbreak,
    "clean maps to Start Jailbreak"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .installedInactive) == .restoreEnvironment,
    "installed inactive maps to Restore Jailbreak Environment"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .repairRequired) == .repairEnvironment,
    "repair-required maps to Repair Current Environment"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .activeDegraded) == .repairEnvironment,
    "active degraded offers targeted repair"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .activeHealthy) == .none,
    "healthy environment does not show a mutation CTA"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .unsupported) == .none,
    "unsupported blocks mutation"
)
expect(
    EnvironmentPrimaryAction.resolve(state: .conflicting) == .none,
    "conflicting blocks mutation"
)

struct FakeEvidenceProvider: EnvironmentEvidenceProviding {
    let target: TargetEvidence
    let runtime: RuntimeEvidence
    let bootstrap: BootstrapEvidence
    let storage: StorageEvidence
    let packages: PackageManagerEvidence
    let conflicts: [EnvironmentIssue]
    let runtimeEnvironment: RuntimeEnvironment?

    func targetEvidence() async -> TargetEvidence { target }
    func runtimeEvidence() async -> RuntimeEvidence { runtime }
    func bootstrapEvidence() async -> BootstrapEvidence { bootstrap }
    func storageEvidence() async -> StorageEvidence { storage }
    func packageManagerEvidence() async -> PackageManagerEvidence { packages }
    func conflictEvidence() async -> [EnvironmentIssue] { conflicts }
    func runtimeEnvironmentEvidence(runtime: RuntimeEvidence, bootstrap: BootstrapEvidence) async -> RuntimeEnvironment? {
        runtimeEnvironment
    }
}

let provider = FakeEvidenceProvider(
    target: TargetEvidence(supported: true, reason: nil),
    runtime: RuntimeEvidence(
        active: false,
        rootHideReportedJailbroken: false,
        processRuntimeActive: false,
        processIsPlatform: false
    ),
    bootstrap: .validRelaxin(identity: "root-A"),
    storage: .sufficient,
    packages: PackageManagerEvidence(sileo: .healthy, zebra: .notInstalled),
    conflicts: [],
    runtimeEnvironment: nil
)
let snapshot = await EnvironmentInspector(provider: provider).inspect()
expect(snapshot.bootstrap == .validRelaxin(identity: "root-A"), "inspector preserves bootstrap evidence")
expect(snapshot.historicalHint == .none, "inspector does not synthesize historical jailbreak hints")

let extendedProvider = FakeEvidenceProvider(
    target: TargetEvidence(supported: false, reason: "production profile not yet verified"),
    runtime: RuntimeEvidence(
        active: false,
        rootHideReportedJailbroken: false,
        processRuntimeActive: false,
        processIsPlatform: false
    ),
    bootstrap: .absent,
    storage: .sufficient,
    packages: PackageManagerEvidence(sileo: .notInstalled, zebra: .notInstalled),
    conflicts: [],
    runtimeEnvironment: RuntimeEnvironment(
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
)
let extendedSnapshot = await EnvironmentInspector(provider: extendedProvider).inspect()
expect(
    extendedSnapshot.runtimeCompatibilityAdmission?.status == .recognized,
    "inspector surfaces announced 0.5.2 compatibility without promoting it to production support"
)
expect(
    extendedSnapshot.runtimeCompatibilityAdmission?.blockers.contains(.backendImplementationMissing) == true,
    "inspector preserves the backend implementation blocker"
)
expect(
    extendedSnapshot.runtimeCompatibilityAdmission?.allowsExecution == false,
    "inspector keeps unverified new-system execution fail-closed"
)

let extendedGate = CompatibilityGate.evaluate(extendedSnapshot)
if case .unsupported(let issue) = extendedGate.disposition {
    expect(
        issue.code == "runtime-backend-validation-required",
        "compatibility gate reports the explicit new-system validation boundary"
    )
} else {
    expect(false, "unverified new-system compatibility must remain unsupported for mutation")
}

if failures == 0 { print("ok home-environment-routing") }
exit(failures == 0 ? 0 : 1)
