import Foundation

enum RuntimeCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case activateRuntime
    case restoreRuntime
    case reuseBootstrap
    case installBootstrap
    case repairBootstrap
    case verifyRuntime
    case verifyBootstrap
    case installPackageManager
    case repairPackageManager
    case publishTrustCache
    case userspaceReboot
    case stealthCompatibility
    case structuredDiagnostics
    case baselineIntegrityValidation
    case hardwareRegistryV2
    case userspaceRebootV2
    case missingTargetPathRepair
}

enum BackendMaturity: String, CaseIterable, Codable, Hashable, Sendable {
    case stable
    case experimental
    case legacy

    var automaticRank: Int {
        switch self {
        case .stable: 0
        case .legacy: 1
        case .experimental: 2
        }
    }
}

enum RuntimeSupportLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case supported
    case experimental
    case partial
    case recoveryOnly
    case unsupported
}
