import Foundation

enum CompatibilityDisposition: Equatable, Sendable {
    case ready
    case risky([EnvironmentIssue])
    case repairRequired([EnvironmentIssue])
    case unsupported(EnvironmentIssue)
    case conflicting(EnvironmentIssue)

    var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var isConflicting: Bool {
        if case .conflicting = self { return true }
        return false
    }
}

enum CompatibilityGate {
    struct Result: Equatable, Sendable {
        let disposition: CompatibilityDisposition
    }

    static func evaluate(
        _ snapshot: EnvironmentSnapshot,
        requirements: Set<RuntimeCapability>? = nil
    ) -> Result {
        if let resolution = snapshot.runtimeResolution {
            if resolution.supportLevel == .unsupported || !resolution.isResolved {
                if let admission = snapshot.runtimeCompatibilityAdmission,
                   admission.status != .unsupported
                {
                    return Result(disposition: .unsupported(admissionIssue(admission)))
                }
                let reason = resolution.rejectedCandidates.first?.reasonCode.rawValue
                    ?? "runtime_resolution_unavailable"
                return Result(
                    disposition: .unsupported(
                        EnvironmentIssue(code: reason, message: "No compatible runtime profile and backend could be resolved")
                    )
                )
            }
            if let requirements, !resolution.supports(requirements) {
                let missing = requirements.subtracting(resolution.capabilities)
                    .map(\.rawValue)
                    .sorted()
                    .joined(separator: ",")
                return Result(
                    disposition: .unsupported(
                        EnvironmentIssue(
                            code: "runtime-capability-missing",
                            message: "The selected runtime backend is missing required capabilities: \(missing)"
                        )
                    )
                )
            }
        } else if let admission = snapshot.runtimeCompatibilityAdmission,
                  admission.status != .unsupported
        {
            return Result(disposition: .unsupported(admissionIssue(admission)))
        } else if !snapshot.target.supported {
            // Compatibility fallback for synthetic/legacy test providers. The
            // production provider always supplies a RuntimeResolution in Fix13.
            return Result(
                disposition: .unsupported(
                    EnvironmentIssue(
                        code: "unsupported-target",
                        message: snapshot.target.reason ?? "Unsupported target"
                    )
                )
            )
        }

        if let conflict = snapshot.conflicts.first {
            return Result(disposition: .conflicting(conflict))
        }

        switch snapshot.bootstrap {
        case .incomplete(let reason):
            return Result(
                disposition: .repairRequired([
                    EnvironmentIssue(code: "bootstrap-incomplete", message: reason)
                ])
            )
        case .ambiguous(let count):
            return Result(
                disposition: .repairRequired([
                    EnvironmentIssue(
                        code: "bootstrap-ambiguous",
                        message: "Found \(count) candidate bootstrap roots"
                    )
                ])
            )
        case .absent where snapshot.runtime.active:
            return Result(
                disposition: .repairRequired([
                    EnvironmentIssue(
                        code: "runtime-without-bootstrap",
                        message: "Runtime is active but no RELAXIN-X bootstrap is visible"
                    )
                ])
            )
        case .absent, .validRelaxin:
            break
        }

        if snapshot.runtime.active,
           snapshot.bootstrap.isValidRelaxin,
           !snapshot.packageManagers.hasInstalledComponent
        {
            return Result(
                disposition: .repairRequired([
                    EnvironmentIssue(
                        code: "package-manager-missing",
                        message: "No installed package manager could be verified"
                    )
                ])
            )
        }

        if snapshot.runtime.active && snapshot.packageManagers.requiresRepair {
            return Result(
                disposition: .repairRequired([
                    EnvironmentIssue(
                        code: "package-manager-repair",
                        message: "A package manager requires repair"
                    )
                ])
            )
        }

        var warnings: [EnvironmentIssue] = []
        if !snapshot.storage.hasSufficientSpace {
            warnings.append(
                EnvironmentIssue(
                    code: "low-storage",
                    message: "Available storage is below the conservative operation minimum"
                )
            )
        }
        if snapshot.packageManagers.hasDegradedComponent {
            warnings.append(
                EnvironmentIssue(
                    code: "package-manager-degraded",
                    message: "A package manager has degraded health"
                )
            )
        }
        if let resolution = snapshot.runtimeResolution, resolution.supportLevel == .partial {
            warnings.append(
                EnvironmentIssue(
                    code: "runtime-partial-support",
                    message: "The selected runtime backend does not provide every optional capability"
                )
            )
        }
        return Result(disposition: warnings.isEmpty ? .ready : .risky(warnings))
    }

    private static func admissionIssue(
        _ admission: RuntimeCompatibilityAdmission
    ) -> EnvironmentIssue {
        if admission.blockers.contains(.baselineIntegrityMissing) {
            let missing = admission.missingBaselineIntegrity
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
            return EnvironmentIssue(
                code: "runtime-baseline-evidence-missing",
                message: "The announced runtime path is recognized, but required baseline evidence is missing: \(missing)"
            )
        }
        if admission.blockers.contains(.hostContractIncomplete) {
            return EnvironmentIssue(
                code: "runtime-host-contract-incomplete",
                message: "The announced runtime path is recognized, but the RELAXIN-X host compatibility contract is incomplete"
            )
        }
        if admission.blockers.contains(.backendImplementationMissing) {
            return EnvironmentIssue(
                code: "runtime-backend-validation-required",
                message: "The announced runtime path is recognized, but no independently verified backend implementation is registered"
            )
        }
        if admission.blockers.contains(.deviceValidationRequired) {
            return EnvironmentIssue(
                code: "runtime-device-validation-required",
                message: "The host path is ready, but device validation is required before execution can be enabled"
            )
        }
        if admission.status == .verified {
            return EnvironmentIssue(
                code: "runtime-profile-registration-required",
                message: "Compatibility evidence is verified, but production runtime routing has not been registered"
            )
        }
        return EnvironmentIssue(
            code: "runtime-compatibility-unavailable",
            message: "The runtime compatibility path is not executable"
        )
    }
}
