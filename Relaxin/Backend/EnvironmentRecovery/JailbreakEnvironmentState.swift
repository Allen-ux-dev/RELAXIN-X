import Foundation

enum JailbreakEnvironmentState: Equatable, Sendable {
    case inspecting
    case unsupported
    case conflicting
    case clean
    case installedInactive
    case activating
    case activeHealthy
    case activeDegraded
    case repairRequired
}

enum EnvironmentStateResolver {
    static func resolve(
        snapshot: EnvironmentSnapshot,
        gate: CompatibilityGate.Result
    ) -> JailbreakEnvironmentState {
        switch gate.disposition {
        case .unsupported:
            return .unsupported
        case .conflicting:
            return .conflicting
        case .repairRequired:
            return .repairRequired
        case .ready, .risky:
            break
        }

        if snapshot.runtime.active {
            return snapshot.packageManagers.hasDegradedComponent
                ? .activeDegraded
                : .activeHealthy
        }

        if snapshot.bootstrap.isValidRelaxin {
            return .installedInactive
        }

        return .clean
    }
}
