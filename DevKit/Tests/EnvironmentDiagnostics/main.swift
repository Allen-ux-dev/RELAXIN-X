import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

let generation = EnvironmentGeneration(
    relaxinBuild: "12",
    bootstrapGeneration: "1900",
    baseBinGeneration: "fix12",
    environmentSchema: 1,
    profileRulesVersion: 2
)
let snapshot = EnvironmentSnapshot(
    target: TargetEvidence(supported: true, reason: nil),
    runtime: RuntimeEvidence(
        active: false,
        rootHideReportedJailbroken: false,
        processRuntimeActive: false,
        processIsPlatform: false
    ),
    bootstrap: .validRelaxin(identity: "do-not-export-root-identity"),
    storage: .sufficient,
    packageManagers: PackageManagerEvidence(
        sileo: .healthy,
        zebra: .degraded(reason: "sources_missing")
    ),
    conflicts: [],
    historicalHint: .previouslyJailbroken,
    fingerprint: EnvironmentFingerprint(
        hardwareIdentifier: "do-not-export-hardware-fingerprint",
        osVersion: "17.0",
        osBuild: "21A329"
    ),
    generation: generation,
    inspectedAt: Date(timeIntervalSince1970: 100)
)
let checkpoint = EnvironmentCheckpoint(
    operation: .restoreEnvironment,
    completedStages: [.preflight, .prepare],
    fingerprint: .unknown,
    generation: generation,
    verifiedAt: Date(timeIntervalSince1970: 90)
)
let outcome = EnvironmentCheckpointLoadOutcome(
    checkpoint: checkpoint,
    diagnostic: nil
)

let report = EnvironmentDiagnosticReport.make(
    stage: "environment_check",
    state: .installedInactive,
    snapshot: snapshot,
    checkpointOutcome: outcome,
    generatedAt: Date(timeIntervalSince1970: 110)
)

expect(report.stage == "environment_check", "report preserves stage")
expect(report.state == "installedInactive", "report uses stable state identifier")
expect(report.generation == generation, "report carries current generation")
expect(report.checkpoint.status == "verified", "report summarizes validated checkpoint")
expect(report.checkpoint.completedStages == ["preflight", "prepare"],
       "report exposes only verified checkpoint stages")
expect(report.findings.contains(where: { $0.code == "zebra_degraded" }),
       "report includes package-manager evidence finding")

let encoded = String(data: try! JSONEncoder().encode(report), encoding: .utf8)!
expect(!encoded.contains("do-not-export-root-identity"), "report does not export jbroot identity")
expect(!encoded.contains("do-not-export-hardware-fingerprint"), "report does not export device fingerprint")

let stale = EnvironmentDiagnosticReport.make(
    stage: "restore_admission",
    state: .installedInactive,
    snapshot: snapshot,
    checkpointOutcome: EnvironmentCheckpointLoadOutcome(
        checkpoint: nil,
        diagnostic: "checkpoint_stale: relaxin_build_changed"
    ),
    generatedAt: Date(timeIntervalSince1970: 111)
)
expect(stale.checkpoint.status == "stale", "stale checkpoint gets structured status")
expect(stale.findings.contains(where: { $0.code == "checkpoint_stale" }),
       "stale checkpoint reason becomes a finding")

let missingPackageManagersSnapshot = EnvironmentSnapshot(
    target: TargetEvidence(supported: true, reason: nil),
    runtime: RuntimeEvidence(
        active: true,
        rootHideReportedJailbroken: true,
        processRuntimeActive: true,
        processIsPlatform: true
    ),
    bootstrap: .validRelaxin(identity: "do-not-export-missing-pm-root"),
    storage: .sufficient,
    packageManagers: PackageManagerEvidence(sileo: .notInstalled, zebra: .notInstalled),
    conflicts: [],
    historicalHint: .previouslyJailbroken,
    generation: generation,
    inspectedAt: Date(timeIntervalSince1970: 120)
)
let missingPackageManagersReport = EnvironmentDiagnosticReport.make(
    stage: "environment_check",
    state: .repairRequired,
    snapshot: missingPackageManagersSnapshot,
    checkpointOutcome: EnvironmentCheckpointLoadOutcome(checkpoint: nil, diagnostic: "checkpoint_missing"),
    generatedAt: Date(timeIntervalSince1970: 121)
)
expect(missingPackageManagersReport.findings.contains(where: { $0.code == "package_manager_missing" }),
       "valid bootstrap with no installed package manager is diagnostic")

let runtimeResolution = RuntimeResolution(
    environmentIdentity: "private-device-identity",
    profileID: "profile-a",
    profileDisplayName: "Profile A",
    backendID: "backend-a",
    backendDisplayName: "Backend A",
    backendMaturity: .stable,
    backendGeneration: 3,
    supportLevel: .partial,
    capabilities: [.restoreRuntime, .verifyRuntime],
    missingCapabilities: [.userspaceReboot],
    warnings: ["optional capability unavailable"],
    rejectedCandidates: [
        RuntimeRejectedCandidate(
            profileID: "other",
            backendID: "other-backend",
            reasonCode: .backendCapabilityMissing,
            detail: "private detail must not be exported"
        )
    ],
    resolutionGeneration: 2
)
let resolutionSnapshot = EnvironmentSnapshot(
    target: TargetEvidence(supported: true, reason: nil),
    runtime: snapshot.runtime,
    bootstrap: snapshot.bootstrap,
    storage: snapshot.storage,
    packageManagers: snapshot.packageManagers,
    conflicts: snapshot.conflicts,
    historicalHint: snapshot.historicalHint,
    fingerprint: snapshot.fingerprint,
    generation: snapshot.generation,
    runtimeResolution: runtimeResolution,
    inspectedAt: snapshot.inspectedAt
)
let resolutionReport = EnvironmentDiagnosticReport.make(
    stage: "runtime_resolution",
    state: .installedInactive,
    snapshot: resolutionSnapshot,
    checkpointOutcome: outcome,
    generatedAt: Date(timeIntervalSince1970: 122)
)
expect(resolutionReport.runtimeResolution?.profileID == "profile-a", "diagnostics include profile ID")
expect(resolutionReport.runtimeResolution?.backendID == "backend-a", "diagnostics include backend ID")
expect(resolutionReport.runtimeResolution?.capabilities.contains("restoreRuntime") == true, "diagnostics include capabilities")
expect(resolutionReport.runtimeResolution?.rejectedCandidateReasonCodes == ["backend_capability_missing"], "diagnostics expose reason codes only")
let resolutionJSON = String(data: try! JSONEncoder().encode(resolutionReport), encoding: .utf8)!
expect(!resolutionJSON.contains("private-device-identity"), "diagnostics do not export runtime environment identity")
expect(!resolutionJSON.contains("private detail must not be exported"), "diagnostics do not export rejection details")

if failures == 0 { print("ok environment-diagnostics") }
exit(failures == 0 ? 0 : 1)
