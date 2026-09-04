import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

let fingerprintA = EnvironmentFingerprint(
    hardwareIdentifier: "iPhone15,4",
    osVersion: "17.0",
    osBuild: "21A329"
)
let fingerprintB = EnvironmentFingerprint(
    hardwareIdentifier: "iPhone15,5",
    osVersion: "17.0",
    osBuild: "21A329"
)
let generationA = EnvironmentGeneration(
    relaxinBuild: "12",
    bootstrapGeneration: "1900",
    baseBinGeneration: "A",
    environmentSchema: 1,
    profileRulesVersion: 1
)
let generationB = EnvironmentGeneration(
    relaxinBuild: "13",
    bootstrapGeneration: "1900",
    baseBinGeneration: "A",
    environmentSchema: 1,
    profileRulesVersion: 1
)

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
let url = directory.appendingPathComponent("checkpoint.json")
let store = EnvironmentCheckpointStore(fileURL: url)
let checkpoint = EnvironmentCheckpoint(
    operation: .restoreEnvironment,
    completedStages: [.preflight, .prepare],
    fingerprint: fingerprintA,
    generation: generationA,
    verifiedAt: Date(timeIntervalSince1970: 1)
)
try store.save(checkpoint)
expect(
    store.loadValidated(for: fingerprintA, generation: generationA) == checkpoint,
    "matching checkpoint loads"
)
let deviceMismatch = store.loadOutcome(for: fingerprintB, generation: generationA)
expect(deviceMismatch.checkpoint == nil, "device fingerprint mismatch invalidates checkpoint")
expect(deviceMismatch.diagnostic?.contains("hardware_identifier_changed") == true,
       "device mismatch explains which identity changed")
let generationMismatch = store.loadOutcome(for: fingerprintA, generation: generationB)
expect(generationMismatch.checkpoint == nil, "generation mismatch invalidates checkpoint")
expect(generationMismatch.diagnostic?.contains("relaxin_build_changed") == true,
       "generation mismatch explains which generation changed")

try Data("{broken".utf8).write(to: url, options: [.atomic])
let corrupt = store.loadOutcome(for: fingerprintA, generation: generationA)
expect(corrupt.checkpoint == nil, "corrupt checkpoint cannot resume")
expect(corrupt.diagnostic?.contains("decode") == true, "corrupt checkpoint returns a decode diagnostic")


let runtimeIdentityA = RuntimeResolutionIdentity(
    profileID: "profile-a",
    backendID: "backend-a",
    backendGeneration: 1,
    resolutionGeneration: 1
)
let runtimeIdentityB = RuntimeResolutionIdentity(
    profileID: "profile-a",
    backendID: "backend-b",
    backendGeneration: 2,
    resolutionGeneration: 1
)
let runtimeCheckpoint = EnvironmentCheckpoint(
    operation: .restoreEnvironment,
    completedStages: [.preflight],
    fingerprint: fingerprintA,
    generation: generationA,
    runtimeResolutionIdentity: runtimeIdentityA,
    verifiedAt: Date(timeIntervalSince1970: 2)
)
try store.save(runtimeCheckpoint)
expect(
    store.loadValidated(
        for: fingerprintA,
        generation: generationA,
        runtimeResolutionIdentity: runtimeIdentityA
    ) == runtimeCheckpoint,
    "matching runtime resolution identity resumes"
)
let runtimeMismatch = store.loadOutcome(
    for: fingerprintA,
    generation: generationA,
    runtimeResolutionIdentity: runtimeIdentityB
)
expect(runtimeMismatch.checkpoint == nil, "backend identity change invalidates resumable checkpoint")
expect(runtimeMismatch.diagnostic?.contains("runtime_backend_changed") == true,
       "backend identity mismatch is diagnostic")

// A Fix13.10 checkpoint has no Fix14 generation fields. It must decode as legacy
// and be rejected as stale, never as corrupt/undecodable.
let legacyCheckpoint = EnvironmentCheckpoint(
    operation: .restoreEnvironment,
    completedStages: [.preflight],
    fingerprint: fingerprintA,
    generation: generationA,
    runtimeResolutionIdentity: runtimeIdentityA,
    verifiedAt: Date(timeIntervalSince1970: 3)
)
let legacyEncoded = try JSONEncoder().encode(legacyCheckpoint)
var legacyObject = try JSONSerialization.jsonObject(with: legacyEncoded) as! [String: Any]
var legacyGeneration = legacyObject["generation"] as! [String: Any]
for key in ["upstreamBaselineID", "runtimeBackendGeneration", "runtimeResolutionGeneration"] {
    legacyGeneration.removeValue(forKey: key)
}
legacyGeneration["runtimeAbstractionSchema"] = 1
legacyObject["generation"] = legacyGeneration
if var identity = legacyObject["runtimeResolutionIdentity"] as? [String: Any] {
    identity.removeValue(forKey: "baselineID")
    legacyObject["runtimeResolutionIdentity"] = identity
}
let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
try legacyData.write(to: url, options: [.atomic])
let legacyOutcome = store.loadOutcome(
    for: fingerprintA,
    generation: EnvironmentGeneration.current(relaxinBuild: "14"),
    runtimeResolutionIdentity: RuntimeResolutionIdentity(
        profileID: "profile-a",
        baselineID: "relaxin.upstream.v0.5.0.20260826",
        backendID: "backend-a",
        backendGeneration: 2,
        resolutionGeneration: 2
    )
)
expect(legacyOutcome.checkpoint == nil, "legacy checkpoint does not resume across Fix14 generation")
expect(legacyOutcome.diagnostic?.contains("checkpoint_stale") == true, "legacy checkpoint is stale rather than corrupt")
expect(legacyOutcome.diagnostic?.contains("decode_failed") != true, "legacy checkpoint decoder remains backward compatible")

try? FileManager.default.removeItem(at: directory)
if failures == 0 { print("ok environment-checkpoint") }
exit(failures == 0 ? 0 : 1)
