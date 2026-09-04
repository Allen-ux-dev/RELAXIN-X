import Foundation

private var failures = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard !condition() else { return }
    print("not ok \(message)")
    failures += 1
}

final class SuccessfulProvider: EnvironmentEvidenceProviding {
    let startsWithBootstrap: Bool
    var didRun = false

    init(startsWithBootstrap: Bool) {
        self.startsWithBootstrap = startsWithBootstrap
    }

    func targetEvidence() async -> TargetEvidence {
        TargetEvidence(supported: true, reason: nil)
    }
    func runtimeEvidence() async -> RuntimeEvidence {
        RuntimeEvidence(
            active: didRun,
            rootHideReportedJailbroken: didRun,
            processRuntimeActive: didRun,
            processIsPlatform: didRun
        )
    }
    func bootstrapEvidence() async -> BootstrapEvidence {
        (startsWithBootstrap || didRun) ? .validRelaxin(identity: "root-success") : .absent
    }
    func storageEvidence() async -> StorageEvidence { .sufficient }
    func packageManagerEvidence() async -> PackageManagerEvidence {
        PackageManagerEvidence(sileo: .healthy, zebra: .notInstalled)
    }
    func conflictEvidence() async -> [EnvironmentIssue] { [] }
}

final class FixedProvider: EnvironmentEvidenceProviding {
    let target: TargetEvidence
    let runtime: RuntimeEvidence
    let bootstrap: BootstrapEvidence
    let conflicts: [EnvironmentIssue]

    init(
        target: TargetEvidence,
        runtime: RuntimeEvidence,
        bootstrap: BootstrapEvidence,
        conflicts: [EnvironmentIssue]
    ) {
        self.target = target
        self.runtime = runtime
        self.bootstrap = bootstrap
        self.conflicts = conflicts
    }

    func targetEvidence() async -> TargetEvidence { target }
    func runtimeEvidence() async -> RuntimeEvidence { runtime }
    func bootstrapEvidence() async -> BootstrapEvidence { bootstrap }
    func storageEvidence() async -> StorageEvidence { .sufficient }
    func packageManagerEvidence() async -> PackageManagerEvidence {
        PackageManagerEvidence(sileo: .healthy, zebra: .notInstalled)
    }
    func conflictEvidence() async -> [EnvironmentIssue] { conflicts }
}

final class Recorder: RecoveryOperationExecuting {
    var intents: [RecoveryExecutionIntent] = []
    let onExecute: () -> Void

    init(onExecute: @escaping () -> Void = {}) {
        self.onExecute = onExecute
    }

    func execute(_ intent: RecoveryExecutionIntent) async throws {
        intents.append(intent)
        onExecute()
    }
}

let restoreProvider = SuccessfulProvider(startsWithBootstrap: true)
let recorder = Recorder { restoreProvider.didRun = true }
let coordinator = EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: restoreProvider),
    executor: recorder
)
try await coordinator.start(.restoreEnvironment)
expect(recorder.intents.count == 1, "restore executes one existing-engine intent")
if let intent = recorder.intents.first {
    expect(intent.reestablishesRuntime, "restore re-establishes runtime")
    expect(intent.bootstrapStrategy == .reuseExisting, "restore reuses existing bootstrap")
    expect(!intent.allowsFreshBootstrapInstall, "restore cannot request fresh bootstrap install")
}

let unsupportedProvider = FixedProvider(
    target: TargetEvidence(supported: false, reason: "unsupported"),
    runtime: RuntimeEvidence(
        active: false,
        rootHideReportedJailbroken: false,
        processRuntimeActive: false,
        processIsPlatform: false
    ),
    bootstrap: .validRelaxin(identity: "root-B"),
    conflicts: []
)
let blockedRecorder = Recorder()
let blocked = EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: unsupportedProvider),
    executor: blockedRecorder
)
do {
    try await blocked.start(.restoreEnvironment)
    expect(false, "unsupported restore must throw")
} catch {
    expect(blockedRecorder.intents.isEmpty, "unsupported restore never reaches executor")
}

let cleanProvider = SuccessfulProvider(startsWithBootstrap: false)
let cleanRecorder = Recorder { cleanProvider.didRun = true }
try await EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: cleanProvider),
    executor: cleanRecorder
).start(.freshInstall)
expect(cleanRecorder.intents.first?.bootstrapStrategy == .freshInstall,
       "clean fresh install admits fresh bootstrap strategy")

final class DegradedAfterRunProvider: EnvironmentEvidenceProviding {
    var didRun = false
    func targetEvidence() async -> TargetEvidence { TargetEvidence(supported: true, reason: nil) }
    func runtimeEvidence() async -> RuntimeEvidence {
        RuntimeEvidence(
            active: didRun,
            rootHideReportedJailbroken: didRun,
            processRuntimeActive: didRun,
            processIsPlatform: didRun
        )
    }
    func bootstrapEvidence() async -> BootstrapEvidence { .validRelaxin(identity: "root-C") }
    func storageEvidence() async -> StorageEvidence { .sufficient }
    func packageManagerEvidence() async -> PackageManagerEvidence {
        PackageManagerEvidence(
            sileo: .healthy,
            zebra: didRun ? .degraded(reason: "still degraded") : .notInstalled
        )
    }
    func conflictEvidence() async -> [EnvironmentIssue] { [] }
}

final class MutatingRecorder: RecoveryOperationExecuting {
    let provider: DegradedAfterRunProvider
    init(provider: DegradedAfterRunProvider) { self.provider = provider }
    func execute(_ intent: RecoveryExecutionIntent) async throws { provider.didRun = true }
}

let degradedProvider = DegradedAfterRunProvider()
let checkpointDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
let checkpointStore = EnvironmentCheckpointStore(
    fileURL: checkpointDirectory.appendingPathComponent("checkpoint.json")
)
let degradedCoordinator = EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: degradedProvider),
    executor: MutatingRecorder(provider: degradedProvider),
    checkpointStore: checkpointStore
)
do {
    try await degradedCoordinator.start(.restoreEnvironment)
    expect(false, "executor success cannot bypass a degraded fresh final inspection")
} catch {
    expect(true, "degraded final inspection rejects overall success")
}
let failedCheckpoint = checkpointStore.loadValidated(
    for: .unknown,
    generation: .baseline
)
expect(failedCheckpoint?.completedStages.contains(.execute) == true,
       "verified execute stage may checkpoint")
expect(failedCheckpoint?.completedStages.contains(.bootstrap) == true,
       "verified bootstrap stage may checkpoint")
expect(failedCheckpoint?.completedStages.contains(.packageManager) == false,
       "failed package-manager postcondition is never checkpointed")
expect(failedCheckpoint?.completedStages.contains(.verify) == false,
       "failed overall verification is never checkpointed")
try? FileManager.default.removeItem(at: checkpointDirectory)

final class MissingPackageManagersAfterRunProvider: EnvironmentEvidenceProviding {
    var didRun = false

    func targetEvidence() async -> TargetEvidence { TargetEvidence(supported: true, reason: nil) }
    func runtimeEvidence() async -> RuntimeEvidence {
        RuntimeEvidence(
            active: didRun,
            rootHideReportedJailbroken: didRun,
            processRuntimeActive: didRun,
            processIsPlatform: didRun
        )
    }
    func bootstrapEvidence() async -> BootstrapEvidence { .validRelaxin(identity: "root-missing-pm") }
    func storageEvidence() async -> StorageEvidence { .sufficient }
    func packageManagerEvidence() async -> PackageManagerEvidence {
        didRun
            ? PackageManagerEvidence(sileo: .notInstalled, zebra: .notInstalled)
            : PackageManagerEvidence(sileo: .healthy, zebra: .notInstalled)
    }
    func conflictEvidence() async -> [EnvironmentIssue] { [] }
}

final class MissingPackageManagersRecorder: RecoveryOperationExecuting {
    let provider: MissingPackageManagersAfterRunProvider
    init(provider: MissingPackageManagersAfterRunProvider) { self.provider = provider }
    func execute(_ intent: RecoveryExecutionIntent) async throws { provider.didRun = true }
}

let missingManagersProvider = MissingPackageManagersAfterRunProvider()
let missingManagersCheckpointDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
let missingManagersCheckpointStore = EnvironmentCheckpointStore(
    fileURL: missingManagersCheckpointDirectory.appendingPathComponent("checkpoint.json")
)
let missingManagersCoordinator = EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: missingManagersProvider),
    executor: MissingPackageManagersRecorder(provider: missingManagersProvider),
    checkpointStore: missingManagersCheckpointStore
)
do {
    try await missingManagersCoordinator.start(.restoreEnvironment)
    expect(false, "missing package managers cannot be accepted after executor success")
} catch {
    expect(true, "missing package managers reject package-manager postcondition")
}
let missingManagersCheckpoint = missingManagersCheckpointStore.loadValidated(
    for: .unknown,
    generation: .baseline
)
expect(missingManagersCheckpoint?.completedStages.contains(.bootstrap) == true,
       "valid bootstrap may checkpoint before package-manager verification")
expect(missingManagersCheckpoint?.completedStages.contains(.packageManager) == false,
       "no installed package manager is never checkpointed")
expect(missingManagersCheckpoint?.completedStages.contains(.verify) == false,
       "missing package manager prevents final verification checkpoint")
try? FileManager.default.removeItem(at: missingManagersCheckpointDirectory)

final class RevalidationCounter {
    var count = 0
}

let revalidationProvider = SuccessfulProvider(startsWithBootstrap: true)
let revalidationRecorder = Recorder { revalidationProvider.didRun = true }
let revalidationCounter = RevalidationCounter()
try await EnvironmentRecoveryCoordinator(
    inspector: EnvironmentInspector(provider: revalidationProvider),
    executor: revalidationRecorder,
    stealthRevalidation: { snapshot in
        if snapshot.runtime.active {
            revalidationCounter.count += 1
        }
    }
).start(.restoreEnvironment)
expect(revalidationCounter.count == 1,
       "successful restore revalidates Stealth compatibility after fresh final verification")

if failures == 0 { print("ok environment-recovery-coordinator") }
exit(failures == 0 ? 0 : 1)
