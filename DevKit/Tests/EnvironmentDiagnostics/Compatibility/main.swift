import Foundation

private var failures = 0
private func expectCompatibility(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

let generation = EnvironmentGeneration(
    relaxinBuild: "052-host",
    bootstrapGeneration: "1900",
    baseBinGeneration: "candidate",
    environmentSchema: 1,
    profileRulesVersion: 2
)

let admission = RuntimeCompatibilityAdmission(
    upstreamVersion: "0.5.2",
    status: .recognized,
    allowsExecution: false,
    missingBaselineIntegrity: [],
    blockers: [.backendImplementationMissing]
)

let snapshot = EnvironmentSnapshot(
    target: TargetEvidence(supported: false, reason: "production backend not verified"),
    runtime: RuntimeEvidence(
        active: false,
        rootHideReportedJailbroken: false,
        processRuntimeActive: false,
        processIsPlatform: false
    ),
    bootstrap: .absent,
    storage: .sufficient,
    packageManagers: PackageManagerEvidence(sileo: .notInstalled, zebra: .notInstalled),
    conflicts: [],
    historicalHint: .none,
    fingerprint: EnvironmentFingerprint(
        hardwareIdentifier: "private-device-id",
        osVersion: "26.0.1",
        osBuild: "23A355"
    ),
    generation: generation,
    runtimeResolution: nil,
    runtimeCompatibilityAdmission: admission,
    inspectedAt: Date(timeIntervalSince1970: 200)
)

let report = EnvironmentDiagnosticReport.make(
    stage: "runtime_compatibility",
    state: .unsupported,
    snapshot: snapshot,
    checkpointOutcome: EnvironmentCheckpointLoadOutcome(
        checkpoint: nil,
        diagnostic: "checkpoint_missing"
    ),
    generatedAt: Date(timeIntervalSince1970: 201)
)

expectCompatibility(report.runtimeCompatibility?.upstreamVersion == "0.5.2", "diagnostics include announced upstream version")
expectCompatibility(report.runtimeCompatibility?.status == "recognized", "diagnostics preserve compatibility status")
expectCompatibility(report.runtimeCompatibility?.allowsExecution == false, "diagnostics preserve fail-closed admission")
expectCompatibility(
    report.runtimeCompatibility?.blockers == ["backendImplementationMissing"],
    "diagnostics expose deterministic compatibility blockers"
)
expectCompatibility(
    report.findings.contains(where: { $0.code == "runtime_backend_validation_required" }),
    "diagnostics include an actionable backend-validation finding"
)

let encoded = String(data: try! JSONEncoder().encode(report), encoding: .utf8)!
expectCompatibility(!encoded.contains("private-device-id"), "compatibility diagnostics do not leak device identifiers")
expectCompatibility(!encoded.contains("23A355"), "compatibility diagnostics do not export exact device build evidence")

if failures == 0 { print("ok environment-diagnostics-compatibility") }
exit(failures == 0 ? 0 : 1)
