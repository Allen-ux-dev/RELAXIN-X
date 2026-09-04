import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

func snapshot(
    bootstrap: BootstrapEvidence = .validRelaxin(identity: "root"),
    sileo: PackageManagerComponentHealth,
    zebra: PackageManagerComponentHealth
) -> EnvironmentSnapshot {
    EnvironmentSnapshot(
        target: TargetEvidence(supported: true, reason: nil),
        runtime: RuntimeEvidence(
            active: true,
            rootHideReportedJailbroken: true,
            processRuntimeActive: true,
            processIsPlatform: true
        ),
        bootstrap: bootstrap,
        storage: .sufficient,
        packageManagers: PackageManagerEvidence(sileo: sileo, zebra: zebra),
        conflicts: [],
        historicalHint: .none,
        inspectedAt: Date(timeIntervalSince1970: 1)
    )
}

let zebraOnly = RepairPlan.derive(from: snapshot(
    sileo: .healthy,
    zebra: .degraded(reason: "missing registration")
))
expect(zebraOnly.actions == [.repairZebra], "only degraded Zebra is targeted")

let sileoSources = RepairPlan.derive(from: snapshot(
    sileo: .degraded(reason: "sileo_sources_missing"),
    zebra: .healthy
))
expect(sileoSources.actions == [.repairPackageSources(.sileo)],
       "damaged Sileo sources produce only source repair")

let zebraSources = RepairPlan.derive(from: snapshot(
    sileo: .healthy,
    zebra: .degraded(reason: "zebra_sources_missing")
))
expect(zebraSources.actions == [.repairPackageSources(.zebra)],
       "damaged Zebra sources produce only Zebra source repair")

let ambiguous = RepairPlan.derive(from: snapshot(
    bootstrap: .ambiguous(count: 2),
    sileo: .healthy,
    zebra: .healthy
))
expect(ambiguous.actions.isEmpty, "ambiguous bootstrap does not trigger automatic mutation")
expect(ambiguous.blockingFindings.contains(where: { $0.code == "bootstrap-ambiguous" }),
       "ambiguous bootstrap produces a blocking diagnostic")

let bothMissing = snapshot(
    sileo: .notInstalled,
    zebra: .notInstalled
)
let missingWithoutPreference = RepairPlan.derive(from: bothMissing)
expect(missingWithoutPreference.actions.isEmpty,
       "missing managers without an explicit preference remain blocked")
expect(missingWithoutPreference.blockingFindings.contains(where: { $0.code == "package-manager-missing" }),
       "missing managers without a preference explain why repair is blocked")

let restoreSelectedSileo = RepairPlan.derive(
    from: bothMissing,
    desiredPackageManagers: [.sileo]
)
expect(restoreSelectedSileo.actions == [.repairSileo],
       "when both managers are absent, selected Sileo becomes the targeted repair")
expect(restoreSelectedSileo.blockingFindings.isEmpty,
       "an explicit Sileo preference makes missing-manager repair actionable")

let restoreSelectedZebra = RepairPlan.derive(
    from: bothMissing,
    desiredPackageManagers: [.zebra]
)
expect(restoreSelectedZebra.actions == [.repairZebra],
       "when both managers are absent, selected Zebra becomes the targeted repair")

let restoreBothSelected = RepairPlan.derive(
    from: bothMissing,
    desiredPackageManagers: [.sileo, .zebra]
)
expect(restoreBothSelected.actions == [.repairSileo, .repairZebra],
       "when both are selected and absent, repair reinstalls both in deterministic order")

expect(!RepairAction.allCasesForContract.contains(where: { $0 == "freshInstall" }),
       "repair action vocabulary has no fresh jailbreak action")

let verifier = PostConditionVerifier()
let zebraStillBroken = snapshot(
    sileo: .healthy,
    zebra: .degraded(reason: "missing registration")
)
expect(
    verifier.verifyRepair(.repairZebra, snapshot: zebraStillBroken) ==
        .failed(reason: "zebra_not_healthy"),
    "repair success is rejected when fresh Zebra health is still degraded"
)
expect(
    verifier.verifyRepair(.repairZebra, snapshot: snapshot(sileo: .healthy, zebra: .healthy)) == .verified,
    "repair success is accepted only after fresh Zebra health is healthy"
)

if failures == 0 { print("ok repair-planning") }
exit(failures == 0 ? 0 : 1)
