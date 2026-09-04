import Foundation

struct EnvironmentDiagnosticFinding: Codable, Equatable, Hashable, Sendable {
    let code: String
    let message: String
}

struct EnvironmentDiagnosticCheckpoint: Codable, Equatable, Sendable {
    let status: String
    let operation: String?
    let completedStages: [String]
    let verifiedAt: Date?
}

struct EnvironmentDiagnosticRuntimeResolution: Codable, Equatable, Sendable {
    let profileID: String
    let backendID: String
    let maturity: String
    let supportLevel: String
    let capabilities: [String]
    let missingCapabilities: [String]
    let warnings: [String]
    let rejectedCandidateReasonCodes: [String]
}

struct EnvironmentDiagnosticReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let stage: String
    let state: String
    let generation: EnvironmentGeneration
    let checkpoint: EnvironmentDiagnosticCheckpoint
    let runtimeResolution: EnvironmentDiagnosticRuntimeResolution?
    let findings: [EnvironmentDiagnosticFinding]

    static func make(
        stage: String,
        state: JailbreakEnvironmentState,
        snapshot: EnvironmentSnapshot,
        checkpointOutcome: EnvironmentCheckpointLoadOutcome,
        generatedAt: Date = Date()
    ) -> EnvironmentDiagnosticReport {
        var findings = evidenceFindings(from: snapshot)
        let checkpoint = checkpointSummary(
            from: checkpointOutcome,
            findings: &findings
        )

        let runtimeResolution = snapshot.runtimeResolution.flatMap { resolution -> EnvironmentDiagnosticRuntimeResolution? in
            guard let profileID = resolution.profileID,
                  let backendID = resolution.backendID,
                  let maturity = resolution.backendMaturity
            else { return nil }
            return EnvironmentDiagnosticRuntimeResolution(
                profileID: profileID,
                backendID: backendID,
                maturity: maturity.rawValue,
                supportLevel: resolution.supportLevel.rawValue,
                capabilities: resolution.capabilities.map(\.rawValue).sorted(),
                missingCapabilities: resolution.missingCapabilities.map(\.rawValue).sorted(),
                warnings: resolution.warnings,
                rejectedCandidateReasonCodes: Array(
                    Set(resolution.rejectedCandidates.map { $0.reasonCode.rawValue })
                ).sorted()
            )
        }

        return EnvironmentDiagnosticReport(
            schemaVersion: 2,
            generatedAt: generatedAt,
            stage: stage,
            state: state.diagnosticIdentifier,
            generation: snapshot.generation,
            checkpoint: checkpoint,
            runtimeResolution: runtimeResolution,
            findings: findings
        )
    }

    private static func checkpointSummary(
        from outcome: EnvironmentCheckpointLoadOutcome,
        findings: inout [EnvironmentDiagnosticFinding]
    ) -> EnvironmentDiagnosticCheckpoint {
        if let checkpoint = outcome.checkpoint {
            return EnvironmentDiagnosticCheckpoint(
                status: "verified",
                operation: checkpoint.operation.rawValue,
                completedStages: checkpoint.completedStages.map(\.rawValue),
                verifiedAt: checkpoint.verifiedAt
            )
        }

        guard let diagnostic = outcome.diagnostic else {
            return EnvironmentDiagnosticCheckpoint(
                status: "unavailable",
                operation: nil,
                completedStages: [],
                verifiedAt: nil
            )
        }

        let status: String
        let code: String
        if diagnostic.hasPrefix("checkpoint_stale") {
            status = "stale"
            code = "checkpoint_stale"
        } else if diagnostic.hasPrefix("checkpoint_decode_failed") {
            status = "invalid"
            code = "checkpoint_decode_failed"
        } else if diagnostic.hasPrefix("checkpoint_read_failed") {
            status = "unreadable"
            code = "checkpoint_read_failed"
        } else if diagnostic == "checkpoint_missing" {
            status = "missing"
            code = "checkpoint_missing"
        } else {
            status = "unavailable"
            code = "checkpoint_unavailable"
        }
        findings.append(
            EnvironmentDiagnosticFinding(code: code, message: diagnostic)
        )
        return EnvironmentDiagnosticCheckpoint(
            status: status,
            operation: nil,
            completedStages: [],
            verifiedAt: nil
        )
    }

    private static func evidenceFindings(
        from snapshot: EnvironmentSnapshot
    ) -> [EnvironmentDiagnosticFinding] {
        var findings = snapshot.conflicts.map {
            EnvironmentDiagnosticFinding(code: $0.code, message: $0.message)
        }

        if let resolution = snapshot.runtimeResolution {
            if resolution.supportLevel == .unsupported {
                findings.append(
                    EnvironmentDiagnosticFinding(
                        code: "runtime_resolution_unsupported",
                        message: "No actionable runtime profile/backend resolution is available"
                    )
                )
            }
        } else if !snapshot.target.supported {
            findings.append(
                EnvironmentDiagnosticFinding(
                    code: "unsupported_target",
                    message: snapshot.target.reason ?? "Unsupported target"
                )
            )
        }

        switch snapshot.bootstrap {
        case .absent, .validRelaxin:
            break
        case .incomplete(let reason):
            findings.append(
                EnvironmentDiagnosticFinding(
                    code: "bootstrap_incomplete",
                    message: reason
                )
            )
        case .ambiguous(let count):
            findings.append(
                EnvironmentDiagnosticFinding(
                    code: "bootstrap_ambiguous",
                    message: "Found \(count) candidate bootstrap roots"
                )
            )
        }

        if !snapshot.storage.hasSufficientSpace {
            findings.append(
                EnvironmentDiagnosticFinding(
                    code: "low_storage",
                    message: "Available storage is below the conservative operation minimum"
                )
            )
        }

        if snapshot.bootstrap.isValidRelaxin && !snapshot.packageManagers.hasInstalledComponent {
            findings.append(
                EnvironmentDiagnosticFinding(
                    code: "package_manager_missing",
                    message: "No supported package manager is installed in the verified RELAXIN-X environment"
                )
            )
        }

        appendPackageManagerFinding(manager: "sileo", health: snapshot.packageManagers.sileo, findings: &findings)
        appendPackageManagerFinding(manager: "zebra", health: snapshot.packageManagers.zebra, findings: &findings)
        return findings
    }

    private static func appendPackageManagerFinding(
        manager: String,
        health: PackageManagerComponentHealth,
        findings: inout [EnvironmentDiagnosticFinding]
    ) {
        switch health {
        case .notInstalled, .healthy:
            return
        case .degraded(let reason):
            findings.append(EnvironmentDiagnosticFinding(code: "\(manager)_degraded", message: reason))
        case .repairRequired(let reason):
            findings.append(EnvironmentDiagnosticFinding(code: "\(manager)_repair_required", message: reason))
        }
    }
}

private extension JailbreakEnvironmentState {
    var diagnosticIdentifier: String {
        switch self {
        case .inspecting: "inspecting"
        case .unsupported: "unsupported"
        case .conflicting: "conflicting"
        case .clean: "clean"
        case .installedInactive: "installedInactive"
        case .activating: "activating"
        case .activeHealthy: "activeHealthy"
        case .activeDegraded: "activeDegraded"
        case .repairRequired: "repairRequired"
        }
    }
}
