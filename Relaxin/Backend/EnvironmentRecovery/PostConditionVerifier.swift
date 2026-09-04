import Foundation

struct PostConditionVerifier: Sendable {
    func decision(
        for stage: RecoveryStage,
        operation: RecoveryOperation,
        snapshot: EnvironmentSnapshot
    ) -> StageDecision {
        switch verify(stage, operation: operation, snapshot: snapshot) {
        case .verified:
            return .skipHealthy
        case .failed:
            return .execute
        }
    }

    func verifyRepair(
        _ action: RepairAction,
        snapshot: EnvironmentSnapshot
    ) -> StageVerification {
        let health: PackageManagerComponentHealth
        let managerName: String
        switch action {
        case .repairSileo,
             .repairPackageSources(.sileo),
             .repairAppRegistration(.sileo):
            health = snapshot.packageManagers.sileo
            managerName = "sileo"
        case .repairZebra,
             .repairPackageSources(.zebra),
             .repairAppRegistration(.zebra):
            health = snapshot.packageManagers.zebra
            managerName = "zebra"
        }

        if case .healthy = health {
            return .verified
        }
        return .failed(reason: "\(managerName)_not_healthy")
    }

    func verify(
        _ stage: RecoveryStage,
        operation: RecoveryOperation,
        snapshot: EnvironmentSnapshot
    ) -> StageVerification {
        switch stage {
        case .preflight:
            let gate = CompatibilityGate.evaluate(snapshot)
            switch gate.disposition {
            case .unsupported:
                return .failed(reason: "unsupported_target")
            case .conflicting:
                return .failed(reason: "conflicting_environment")
            case .repairRequired where operation != .repairEnvironment:
                return .failed(reason: "preflight_requires_repair")
            case .repairRequired, .ready, .risky:
                return .verified
            }

        case .prepare:
            // Preparation means the operation's admission prerequisites still
            // hold. It does not mean a fresh install must already have a root.
            let gate = CompatibilityGate.evaluate(snapshot)
            let state = EnvironmentStateResolver.resolve(snapshot: snapshot, gate: gate)
            switch (operation, state) {
            case (.freshInstall, .clean),
                 (.restoreEnvironment, .installedInactive),
                 (.repairEnvironment, .repairRequired),
                 (.repairEnvironment, .activeDegraded):
                return .verified
            default:
                return .failed(reason: "prepare_state_changed")
            }

        case .execute:
            return snapshot.runtime.active
                ? .verified
                : .failed(reason: "runtime_not_active")

        case .bootstrap:
            return snapshot.bootstrap.isValidRelaxin
                ? .verified
                : .failed(reason: "bootstrap_not_verified")

        case .packageManager:
            guard snapshot.packageManagers.hasInstalledComponent else {
                return .failed(reason: "package_manager_missing")
            }
            if snapshot.packageManagers.requiresRepair {
                return .failed(reason: "package_manager_requires_repair")
            }
            if snapshot.packageManagers.hasDegradedComponent {
                return .failed(reason: "package_manager_degraded")
            }
            return .verified

        case .finalize:
            guard snapshot.runtime.active else {
                return .failed(reason: "runtime_not_active")
            }
            guard snapshot.bootstrap.isValidRelaxin else {
                return .failed(reason: "bootstrap_not_verified")
            }
            return .verified

        case .verify:
            let gate = CompatibilityGate.evaluate(snapshot)
            let state = EnvironmentStateResolver.resolve(snapshot: snapshot, gate: gate)
            return state == .activeHealthy
                ? .verified
                : .failed(reason: "final_state_\(String(describing: state))")
        }
    }
}
