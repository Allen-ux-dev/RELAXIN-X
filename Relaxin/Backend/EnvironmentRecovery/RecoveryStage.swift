import Foundation

enum RecoveryStage: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case preflight
    case prepare
    case execute
    case bootstrap
    case packageManager
    case finalize
    case verify
}

enum StageDecision: Equatable, Sendable {
    case execute
    case skipHealthy
    case stop(reason: String)
}

enum StageVerification: Equatable, Sendable {
    case verified
    case failed(reason: String)
}
