import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func resolution(
    backend: String = "backend-a",
    backendGeneration: Int = 1,
    resolutionGeneration: Int = 1,
    capabilities: Set<RuntimeCapability> = [.activateRuntime, .verifyRuntime, .verifyBootstrap]
) -> RuntimeResolution {
    RuntimeResolution(
        environmentIdentity: "identity",
        profileID: "profile-a",
        profileDisplayName: "Profile",
        backendID: backend,
        backendDisplayName: backend,
        backendMaturity: .stable,
        backendGeneration: backendGeneration,
        supportLevel: .supported,
        capabilities: capabilities,
        missingCapabilities: [],
        warnings: [],
        rejectedCandidates: [],
        resolutionGeneration: resolutionGeneration
    )
}

let selected = resolution()
let selectedIdentity = selected.checkpointIdentity!
let allowed = RuntimeExecutionAdmission.validate(
    selectedIdentity: selectedIdentity,
    freshResolution: selected,
    requirements: [.activateRuntime]
)
require(allowed == .admitted, "matching resolution and capabilities must be admitted")

let switched = RuntimeExecutionAdmission.validate(
    selectedIdentity: selectedIdentity,
    freshResolution: resolution(backend: "backend-b", backendGeneration: 2),
    requirements: [.activateRuntime]
)
require(switched == .resolutionChanged(["runtime_backend_changed", "runtime_backend_generation_changed"]), "backend switch must abort before mutation")

let generationChanged = RuntimeExecutionAdmission.validate(
    selectedIdentity: selectedIdentity,
    freshResolution: resolution(resolutionGeneration: 2),
    requirements: [.activateRuntime]
)
require(generationChanged == .resolutionChanged(["runtime_resolution_generation_changed"]), "resolution schema change must abort")

let missing = RuntimeExecutionAdmission.validate(
    selectedIdentity: selectedIdentity,
    freshResolution: resolution(capabilities: [.verifyRuntime, .verifyBootstrap]),
    requirements: [.activateRuntime, .verifyRuntime]
)
require(missing == .missingCapabilities([.activateRuntime]), "missing operation capability must abort")

print("PASS RuntimeBackendExecution")
