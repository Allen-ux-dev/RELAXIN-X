import Foundation

struct LegacyRelaxinRuntimeBackend: RuntimeBackend {
    static let backendID = "relaxin.current-engine"

    let descriptor = RuntimeBackendDescriptor(
        id: backendID,
        displayName: "RELAXIN-X Current Engine",
        maturity: .stable,
        supportedProfileIDs: [
            RuntimeProfileRegistry.productionProfileID,
            RuntimeProfileRegistry.currentPublicSnapshotID,
        ],
        capabilities: [
            .activateRuntime,
            .restoreRuntime,
            .reuseBootstrap,
            .installBootstrap,
            .repairBootstrap,
            .verifyRuntime,
            .verifyBootstrap,
            .installPackageManager,
            .repairPackageManager,
            .publishTrustCache,
            .userspaceReboot,
            .stealthCompatibility,
            .structuredDiagnostics,
            .baselineIntegrityValidation,
            .hardwareRegistryV2,
        ],
        hardwareClasses: Set(HardwareExecutionClass.allCases),
        minimumEnvironmentSchema: 1,
        backendGeneration: 2
    )

    func validate(environment: RuntimeEnvironment, profile: RuntimeProfile) -> Bool {
        descriptor.supportedProfileIDs.contains(profile.id)
            && profile.matches(environment)
            && environment.hardwareExecutionClass.map(descriptor.hardwareClasses.contains) == true
    }
}
