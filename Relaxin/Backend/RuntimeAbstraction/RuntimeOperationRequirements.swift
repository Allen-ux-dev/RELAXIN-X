import Foundation

enum RuntimeOperationRequirements {
    static func freshInstall(packageManagerSelected: Bool) -> Set<RuntimeCapability> {
        var requirements: Set<RuntimeCapability> = [
            .activateRuntime,
            .installBootstrap,
            .verifyRuntime,
            .verifyBootstrap,
        ]
        if packageManagerSelected {
            requirements.insert(.installPackageManager)
        }
        return requirements
    }

    static let restore: Set<RuntimeCapability> = [
        .restoreRuntime,
        .reuseBootstrap,
        .verifyRuntime,
        .verifyBootstrap,
    ]

    static func repair(
        bootstrap: Bool = false,
        packageManager: Bool = false,
        trustCache: Bool = false
    ) -> Set<RuntimeCapability> {
        var requirements: Set<RuntimeCapability> = []
        if bootstrap { requirements.insert(.repairBootstrap) }
        if packageManager { requirements.insert(.repairPackageManager) }
        if trustCache { requirements.insert(.publishTrustCache) }
        return requirements
    }

    static let stealth: Set<RuntimeCapability> = [.stealthCompatibility]
}
