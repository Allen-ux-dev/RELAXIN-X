import Foundation

private var failures = 0


private extension EnvironmentSnapshot {
    static func fixture(
        targetSupported: Bool,
        runtimeActive: Bool,
        bootstrap: BootstrapEvidence,
        conflicts: [EnvironmentIssue],
        historicalHint: HistoricalEnvironmentHint = .none,
        sileo: PackageManagerComponentHealth = .healthy,
        zebra: PackageManagerComponentHealth = .notInstalled
    ) -> EnvironmentSnapshot {
        EnvironmentSnapshot(
            target: TargetEvidence(supported: targetSupported, reason: targetSupported ? nil : "unsupported target"),
            runtime: RuntimeEvidence(
                active: runtimeActive,
                rootHideReportedJailbroken: runtimeActive,
                processRuntimeActive: runtimeActive,
                processIsPlatform: runtimeActive
            ),
            bootstrap: bootstrap,
            storage: .sufficient,
            packageManagers: PackageManagerEvidence(sileo: sileo, zebra: zebra),
            conflicts: conflicts,
            historicalHint: historicalHint,
            inspectedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

let inactiveInstalled = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .validRelaxin(identity: "root-A"),
    conflicts: []
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: inactiveInstalled,
        gate: CompatibilityGate.evaluate(inactiveInstalled)
    ) == .installedInactive,
    "valid bootstrap + inactive runtime resolves installedInactive"
)

let savedOnly = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .absent,
    conflicts: [],
    historicalHint: .previouslyJailbroken
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: savedOnly,
        gate: CompatibilityGate.evaluate(savedOnly)
    ) == .clean,
    "historical hint cannot create installedInactive"
)

let ambiguous = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .ambiguous(count: 2),
    conflicts: []
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: ambiguous,
        gate: CompatibilityGate.evaluate(ambiguous)
    ) == .repairRequired,
    "ambiguous roots cannot resolve healthy"
)

let unsupported = EnvironmentSnapshot.fixture(
    targetSupported: false,
    runtimeActive: false,
    bootstrap: .absent,
    conflicts: []
)
expect(
    CompatibilityGate.evaluate(unsupported).disposition.isUnsupported,
    "unsupported target blocks before bootstrap state"
)

let conflicting = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .validRelaxin(identity: "root-B"),
    conflicts: [EnvironmentIssue(code: "conflict", message: "conflicting active environment")]
)
expect(
    CompatibilityGate.evaluate(conflicting).disposition.isConflicting,
    "conflicting environment blocks mutation"
)

let activeDegraded = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: true,
    bootstrap: .validRelaxin(identity: "root-C"),
    conflicts: [],
    sileo: .healthy,
    zebra: .degraded(reason: "registration missing")
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: activeDegraded,
        gate: CompatibilityGate.evaluate(activeDegraded)
    ) == .activeDegraded,
    "active runtime with degraded package manager resolves activeDegraded"
)


let inactiveWithoutPackageManager = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .validRelaxin(identity: "root-inactive-missing-pm"),
    conflicts: [],
    sileo: .notInstalled,
    zebra: .notInstalled
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: inactiveWithoutPackageManager,
        gate: CompatibilityGate.evaluate(inactiveWithoutPackageManager)
    ) == .installedInactive,
    "inactive installed environment restores runtime before package-manager repair"
)

let inactiveWithDegradedPackageManager = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: false,
    bootstrap: .validRelaxin(identity: "root-inactive-degraded-pm"),
    conflicts: [],
    sileo: .healthy,
    zebra: .repairRequired(reason: "registration missing")
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: inactiveWithDegradedPackageManager,
        gate: CompatibilityGate.evaluate(inactiveWithDegradedPackageManager)
    ) == .installedInactive,
    "inactive installed environment restores runtime before degraded package-manager repair"
)

let activeWithoutPackageManager = EnvironmentSnapshot.fixture(
    targetSupported: true,
    runtimeActive: true,
    bootstrap: .validRelaxin(identity: "root-D"),
    conflicts: [],
    sileo: .notInstalled,
    zebra: .notInstalled
)
expect(
    EnvironmentStateResolver.resolve(
        snapshot: activeWithoutPackageManager,
        gate: CompatibilityGate.evaluate(activeWithoutPackageManager)
    ) == .repairRequired,
    "active runtime without any verified package manager requires repair"
)

if failures == 0 {
    print("ok environment-state")
}
exit(failures == 0 ? 0 : 1)
