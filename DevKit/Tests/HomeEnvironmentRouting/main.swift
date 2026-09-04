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

    func targetEvidence() async -> TargetEvidence { target }
    func runtimeEvidence() async -> RuntimeEvidence { runtime }
    func bootstrapEvidence() async -> BootstrapEvidence { bootstrap }
    func storageEvidence() async -> StorageEvidence { storage }
    func packageManagerEvidence() async -> PackageManagerEvidence { packages }
    func conflictEvidence() async -> [EnvironmentIssue] { conflicts }
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
    conflicts: []
)
let snapshot = await EnvironmentInspector(provider: provider).inspect()
expect(snapshot.bootstrap == .validRelaxin(identity: "root-A"), "inspector preserves bootstrap evidence")
expect(snapshot.historicalHint == .none, "inspector does not synthesize historical jailbreak hints")

if failures == 0 { print("ok home-environment-routing") }
exit(failures == 0 ? 0 : 1)
