import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

expect(StealthProfileIdentifier.isValid("com.example.notes"), "valid bundle identifier accepted")
expect(!StealthProfileIdentifier.isValid(""), "empty bundle identifier rejected")
expect(!StealthProfileIdentifier.isValid("com.example/bad"), "path-like bundle identifier rejected")
expect(!StealthProfileIdentifier.isValid(String(repeating: "a", count: 256)), "oversized bundle identifier rejected")

let generation = EnvironmentGeneration.current(relaxinBuild: "12")
let resolver = StealthProfileResolver(
    hardRules: [
        "com.aapl.relaxin",
        "org.coolstar.SileoStore",
        "xyz.willy.Zebra",
    ]
)

expect(
    resolver.resolve(
        bundleID: "com.aapl.relaxin",
        userMode: .compatibility,
        runtime: .healthy
    ) == .developer,
    "hard rule protects Relaxin from self-isolation"
)
expect(
    resolver.resolve(
        bundleID: "com.example.notes",
        userMode: .automatic,
        runtime: .healthy
    ) == .compatibility,
    "ordinary automatic app gets conservative compatibility mode"
)
expect(
    resolver.resolve(
        bundleID: "com.example.notes",
        userMode: .automatic,
        runtime: .inactive
    ) == .needsReview,
    "inactive runtime suspends automatic compatibility verification"
)
expect(
    resolver.resolve(
        bundleID: "com.example.devtool",
        userMode: .developer,
        runtime: .inactive
    ) == .developer,
    "developer preference remains explicit while runtime is inactive"
)

let verified = AppStealthProfile(
    bundleIdentifier: "com.example.notes",
    mode: .automatic,
    lastVerifiedGeneration: generation,
    lastVerifiedAt: Date(timeIntervalSince1970: 10)
)
let inspector = StealthHealthInspector(resolver: resolver)
let healthy = inspector.inspect(
    runtime: .healthy,
    profiles: [verified],
    generation: generation
)
expect(healthy.overall == .ready, "verified healthy profile produces ready Stealth health")

let suspended = inspector.inspect(
    runtime: .inactive,
    profiles: [verified],
    generation: generation
)
expect(suspended.overall == .suspended, "rebooted runtime suspends Stealth health")

let changedGeneration = EnvironmentGeneration(
    relaxinBuild: "13",
    bootstrapGeneration: generation.bootstrapGeneration,
    baseBinGeneration: generation.baseBinGeneration,
    environmentSchema: generation.environmentSchema,
    profileRulesVersion: generation.profileRulesVersion + 1
)
let stale = inspector.inspect(
    runtime: .healthy,
    profiles: [verified],
    generation: changedGeneration
)
expect(stale.overall == .needsVerification, "generation change invalidates live profile verification")
expect(stale.affectedBundleIdentifiers == ["com.example.notes"], "only stale profile is affected")

let developer = AppStealthProfile(
    bundleIdentifier: "com.example.devtool",
    mode: .developer,
    lastVerifiedGeneration: generation,
    lastVerifiedAt: Date(timeIntervalSince1970: 11)
)
let disabled = AppStealthProfile(
    bundleIdentifier: "com.example.plain",
    mode: .disabled,
    lastVerifiedGeneration: generation,
    lastVerifiedAt: Date(timeIntervalSince1970: 12)
)
let developerStaleHealth = inspector.inspect(
    runtime: .healthy,
    profiles: [developer],
    generation: changedGeneration
)
expect(
    developerStaleHealth.overall == .needsVerification,
    "developer profile mapping is revalidated after generation change"
)
let reviewProfile = AppStealthProfile(
    bundleIdentifier: "com.example.review",
    mode: .needsReview
)
let reviewHealth = inspector.inspect(
    runtime: .healthy,
    profiles: [reviewProfile],
    generation: generation
)
expect(
    reviewHealth.overall == .needsVerification,
    "Needs Review profile can never report Stealth ready"
)

let invalidated = StealthProfileStore.invalidatingVerification(
    in: [verified, developer, disabled],
    for: changedGeneration
)
expect(invalidated[0].mode == .automatic, "invalidation preserves Automatic preference")
expect(invalidated[1].mode == .developer, "invalidation preserves Developer preference")
expect(invalidated[2].mode == .disabled, "invalidation preserves Disabled preference")
expect(invalidated.allSatisfy { $0.lastVerifiedGeneration == nil }, "generation invalidation clears verification only")

let temp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("relaxin-stealth-\(UUID().uuidString).json")
let store = StealthProfileStore(fileURL: temp)
do {
    try store.save([verified, developer])
    let loaded = try store.load()
    expect(loaded == [verified, developer], "profile store roundtrips explicit preferences")
} catch {
    print("not ok profile store roundtrip: \(error)")
    failures += 1
}
try? FileManager.default.removeItem(at: temp)


let revalidator = StealthProfileRevalidator(resolver: resolver)
expect(
    revalidator.expectedCompatibility(
        bundleID: "com.example.notes",
        userMode: .automatic,
        runtime: .healthy
    ) == true,
    "automatic healthy profile expects RootHide compatibility isolation"
)
expect(
    revalidator.expectedCompatibility(
        bundleID: "com.example.devtool",
        userMode: .developer,
        runtime: .healthy
    ) == false,
    "developer profile expects RootHide compatibility isolation disabled"
)
expect(
    revalidator.expectedCompatibility(
        bundleID: "com.aapl.relaxin",
        userMode: .compatibility,
        runtime: .healthy
    ) == false,
    "hard-rule management app can never request compatibility isolation"
)
expect(
    revalidator.expectedCompatibility(
        bundleID: "com.example.notes",
        userMode: .automatic,
        runtime: .inactive
    ) == nil,
    "inactive runtime has no device mutation expectation"
)

let mismatchedReadback = revalidator.applyingReadback(
    to: verified,
    runtime: .healthy,
    generation: changedGeneration,
    actualCompatibilityEnabled: false,
    verifiedAt: Date(timeIntervalSince1970: 20)
)
expect(
    mismatchedReadback.lastVerifiedGeneration == nil,
    "mismatched RootHide readback remains unverified"
)
let matchedReadback = revalidator.applyingReadback(
    to: verified,
    runtime: .healthy,
    generation: changedGeneration,
    actualCompatibilityEnabled: true,
    verifiedAt: Date(timeIntervalSince1970: 21)
)
expect(
    matchedReadback.lastVerifiedGeneration == changedGeneration,
    "matching RootHide readback commits profile verification"
)

let repairPlan = StealthRepairPlan.derive(from: stale)
expect(
    repairPlan.actions == [.revalidateProfile(bundleIdentifier: "com.example.notes")],
    "Stealth repair targets only affected profile"
)
expect(
    !StealthRepairAction.contractVocabulary.contains("freshInstall"),
    "Stealth repair has no full jailbreak action"
)

if failures == 0 { print("ok stealth-compatibility") }
exit(failures == 0 ? 0 : 1)
