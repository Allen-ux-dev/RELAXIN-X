import Foundation

enum RecoveryOperation: String, Codable, Equatable, Sendable {
    case freshInstall
    case restoreEnvironment
    case repairEnvironment
}

enum RecoveryBootstrapStrategy: String, Codable, Equatable, Sendable {
    case freshInstall
    case reuseExisting
    case preserveExisting
}

struct RecoveryExecutionIntent: Equatable, Sendable {
    let operation: RecoveryOperation
    let reestablishesRuntime: Bool
    let bootstrapStrategy: RecoveryBootstrapStrategy
    let allowsFreshBootstrapInstall: Bool

    static func intent(for operation: RecoveryOperation) -> RecoveryExecutionIntent {
        switch operation {
        case .freshInstall:
            RecoveryExecutionIntent(
                operation: operation,
                reestablishesRuntime: true,
                bootstrapStrategy: .freshInstall,
                allowsFreshBootstrapInstall: true
            )
        case .restoreEnvironment:
            RecoveryExecutionIntent(
                operation: operation,
                reestablishesRuntime: true,
                bootstrapStrategy: .reuseExisting,
                allowsFreshBootstrapInstall: false
            )
        case .repairEnvironment:
            RecoveryExecutionIntent(
                operation: operation,
                reestablishesRuntime: false,
                bootstrapStrategy: .preserveExisting,
                allowsFreshBootstrapInstall: false
            )
        }
    }
}
