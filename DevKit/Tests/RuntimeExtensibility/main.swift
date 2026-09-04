import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL RuntimeExtensibility: \(message)\n", stderr)
        exit(1)
    }
}

let futureVersion = "99.4.7"
let futureBuild = "FUTURE99A1"
let profileID = "test.future.profile"
let backendID = "test.future.backend"

let environment = RuntimeEnvironment(
    deviceIdentifier: "SyntheticFutureDevice,1",
    cpuFamily: 0x4625_04D2,
    architecture: "arm64e",
    osVersion: futureVersion,
    osBuild: futureBuild,
    isSimulator: false,
    environmentSchema: 13,
    hasInstalledBootstrap: false,
    runtimeActive: false
)

let profile = RuntimeProfile(
    id: profileID,
    displayName: "Synthetic Future Runtime",
    osConstraint: .exactVersions([futureVersion]),
    exactBuilds: [futureBuild],
    hardwareClasses: [.pplGFXA13],
    requiredArchitecture: "arm64e",
    requiredBackendCapabilities: [
        .activateRuntime,
        .installBootstrap,
        .verifyRuntime,
        .verifyBootstrap,
    ],
    optionalCapabilities: [.userspaceReboot],
    bootstrapGeneration: "future-bootstrap-1",
    minimumEnvironmentSchema: 13,
    recoveryPolicy: .allowed,
    maturityFloor: .stable
)

let backend = RuntimeBackendDescriptor(
    id: backendID,
    displayName: "Synthetic Future Backend",
    maturity: .stable,
    supportedProfileIDs: [profileID],
    capabilities: [
        .activateRuntime,
        .restoreRuntime,
        .reuseBootstrap,
        .installBootstrap,
        .verifyRuntime,
        .verifyBootstrap,
        .installPackageManager,
        .repairPackageManager,
        .structuredDiagnostics,
    ],
    hardwareClasses: [.pplGFXA13],
    minimumEnvironmentSchema: 13,
    backendGeneration: 42
)

let freshResolution = RuntimeProfileResolver.resolve(
    environment: environment,
    profiles: [profile],
    backends: [backend],
    policy: .recommended
)

expect(freshResolution.isResolved, "future profile/backend did not resolve")
expect(freshResolution.profileID == profileID, "future profile identity mismatch")
expect(freshResolution.backendID == backendID, "future backend identity mismatch")
expect(freshResolution.supportLevel == .partial, "optional capability omission should produce partial support")

let freshRequirements = RuntimeOperationRequirements.freshInstall(packageManagerSelected: true)
expect(freshResolution.supports(freshRequirements), "future resolution did not admit fresh install requirements")

guard let selectedFresh = freshResolution.checkpointIdentity else {
    fputs("FAIL RuntimeExtensibility: future resolution identity missing\n", stderr)
    exit(1)
}
expect(
    RuntimeExecutionAdmission.validate(
        selectedIdentity: selectedFresh,
        freshResolution: freshResolution,
        requirements: freshRequirements
    ) == .admitted,
    "fresh execution admission rejected synthetic future backend"
)

let installedEnvironment = RuntimeEnvironment(
    deviceIdentifier: environment.deviceIdentifier,
    cpuFamily: environment.cpuFamily,
    architecture: environment.architecture,
    osVersion: environment.osVersion,
    osBuild: environment.osBuild,
    isSimulator: false,
    environmentSchema: environment.environmentSchema,
    hasInstalledBootstrap: true,
    runtimeActive: false
)
let restoreResolution = RuntimeProfileResolver.resolve(
    environment: installedEnvironment,
    profiles: [profile],
    backends: [backend],
    policy: .recommended
)
expect(restoreResolution.isResolved, "future installed environment did not resolve")
expect(restoreResolution.supports(RuntimeOperationRequirements.restore), "future backend did not admit restore requirements")

guard let selectedRestore = restoreResolution.checkpointIdentity else {
    fputs("FAIL RuntimeExtensibility: restore resolution identity missing\n", stderr)
    exit(1)
}
expect(
    RuntimeExecutionAdmission.validate(
        selectedIdentity: selectedRestore,
        freshResolution: restoreResolution,
        requirements: RuntimeOperationRequirements.restore
    ) == .admitted,
    "restore execution admission rejected synthetic future backend"
)

print("PASS RuntimeExtensibility")
