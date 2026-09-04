import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

let generation11 = EnvironmentGeneration(
    relaxinBuild: "11",
    bootstrapGeneration: "1900",
    baseBinGeneration: "A",
    environmentSchema: 1,
    profileRulesVersion: 1
)
let generation12 = EnvironmentGeneration(
    relaxinBuild: "12",
    bootstrapGeneration: "1900",
    baseBinGeneration: "A",
    environmentSchema: 1,
    profileRulesVersion: 1
)
let deviceA = EnvironmentFingerprint(
    hardwareIdentifier: "iPhone15,4",
    osVersion: "17.0",
    osBuild: "21A329"
)
let deviceB = EnvironmentFingerprint(
    hardwareIdentifier: "iPhone15,5",
    osVersion: "17.0",
    osBuild: "21A329"
)
let osB = EnvironmentFingerprint(
    hardwareIdentifier: "iPhone15,4",
    osVersion: "17.0.1",
    osBuild: "21A340"
)

let buildChange = StaleStateInvalidator.compare(
    previousGeneration: generation11,
    currentGeneration: generation12,
    previousFingerprint: deviceA,
    currentFingerprint: deviceA
)
expect(buildChange.invalidateCheckpoint, "Relaxin build change invalidates checkpoint")
expect(buildChange.invalidateHealthVerification, "Relaxin build change invalidates health verification")
expect(!buildChange.deleteEnvironment, "generation mismatch never deletes the environment")
expect(buildChange.preserveExplicitProfilePreferences,
       "generation mismatch preserves explicit user profile preferences")

let deviceChange = StaleStateInvalidator.compare(
    previousGeneration: generation12,
    currentGeneration: generation12,
    previousFingerprint: deviceA,
    currentFingerprint: deviceB
)
expect(deviceChange.invalidateCheckpoint, "device change invalidates checkpoint")
expect(deviceChange.invalidateCachedTargetMetadata, "device change invalidates cached target metadata")
expect(deviceChange.invalidateKernelMetadata, "device change invalidates cached kernel metadata")
expect(!deviceChange.deleteEnvironment, "device change never auto-deletes the environment")

let osChange = StaleStateInvalidator.compare(
    previousGeneration: generation12,
    currentGeneration: generation12,
    previousFingerprint: deviceA,
    currentFingerprint: osB
)
expect(osChange.invalidateCachedTargetMetadata, "OS build change invalidates target metadata")
expect(osChange.invalidateKernelMetadata, "OS build change invalidates kernel metadata")

let unchanged = StaleStateInvalidator.compare(
    previousGeneration: generation12,
    currentGeneration: generation12,
    previousFingerprint: deviceA,
    currentFingerprint: deviceA
)
expect(!unchanged.invalidateCheckpoint, "unchanged environment preserves checkpoint")
expect(!unchanged.invalidateHealthVerification, "unchanged environment preserves health verification")
expect(unchanged.preserveExplicitProfilePreferences, "explicit profile preferences remain preserved")
expect(!unchanged.deleteEnvironment, "unchanged environment is non-destructive")

let currentGeneration = EnvironmentGeneration.current(relaxinBuild: "14")
expect(currentGeneration.upstreamBaselineID == "relaxin.upstream.v0.5.0.20260826", "current generation records v0.5.0 baseline")
expect(currentGeneration.runtimeAbstractionSchema == 2, "runtime abstraction schema is 2")
expect(currentGeneration.runtimeBackendGeneration == 2, "runtime backend generation is 2")
expect(currentGeneration.runtimeResolutionGeneration == 2, "runtime resolution generation is 2")
expect(currentGeneration.baseBinGeneration == "public-snapshot-f44e0acf-fix12", "local BaseBin generation stays source-backed until an explicit BaseBin promotion")

let legacyJSON = Data(#"{"relaxinBuild":"13","bootstrapGeneration":"1900","baseBinGeneration":"public-snapshot-f44e0acf-fix12","environmentSchema":1,"profileRulesVersion":2,"runtimeAbstractionSchema":1}"#.utf8)
do {
    let decoded = try JSONDecoder().decode(EnvironmentGeneration.self, from: legacyJSON)
    expect(decoded.upstreamBaselineID == "legacy.unknown", "legacy generation gets explicit baseline identity")
    expect(decoded.runtimeBackendGeneration == 1, "legacy generation defaults backend generation to 1")
    expect(decoded.runtimeResolutionGeneration == 1, "legacy generation defaults resolution generation to 1")
    expect(decoded.runtimeAbstractionSchema == 1, "legacy encoded runtime abstraction schema is preserved")
} catch {
    expect(false, "legacy generation JSON must decode: \(error)")
}

let previousBaseline = EnvironmentGeneration(
    relaxinBuild: "14",
    bootstrapGeneration: currentGeneration.bootstrapGeneration,
    baseBinGeneration: currentGeneration.baseBinGeneration,
    environmentSchema: currentGeneration.environmentSchema,
    profileRulesVersion: currentGeneration.profileRulesVersion,
    runtimeAbstractionSchema: currentGeneration.runtimeAbstractionSchema,
    upstreamBaselineID: "relaxin.upstream.v0.4.9",
    runtimeBackendGeneration: currentGeneration.runtimeBackendGeneration,
    runtimeResolutionGeneration: currentGeneration.runtimeResolutionGeneration
)
let baselineChange = StaleStateInvalidator.compare(
    previousGeneration: previousBaseline,
    currentGeneration: currentGeneration,
    previousFingerprint: deviceA,
    currentFingerprint: deviceA
)
expect(baselineChange.invalidateCheckpoint, "upstream baseline change invalidates checkpoint")
expect(baselineChange.invalidateKernelMetadata, "upstream baseline change invalidates cached kernel metadata")
expect(baselineChange.reasons.contains("upstream_baseline_changed"), "baseline change is diagnostic")

if failures == 0 {
    print("ok environment-generation")
    print("ok environment-generation-v2")
}
exit(failures == 0 ? 0 : 1)
