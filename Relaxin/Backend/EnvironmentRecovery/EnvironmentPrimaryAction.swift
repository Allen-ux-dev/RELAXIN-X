import Foundation

enum EnvironmentPrimaryAction: Equatable, Sendable {
    case startJailbreak
    case restoreEnvironment
    case repairEnvironment
    case none

    static func resolve(state: JailbreakEnvironmentState) -> EnvironmentPrimaryAction {
        switch state {
        case .clean:
            return .startJailbreak
        case .installedInactive:
            return .restoreEnvironment
        case .repairRequired, .activeDegraded:
            return .repairEnvironment
        case .inspecting, .unsupported, .conflicting, .activating, .activeHealthy:
            return .none
        }
    }
}
