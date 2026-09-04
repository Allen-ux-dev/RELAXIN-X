import Combine
import Foundation
import RelaxinEngine
import UIKit

@MainActor
private final class EngineBackgroundTaskLease {
    private(set) var didExpire = false
    private var identifier = UIBackgroundTaskIdentifier.invalid

    static func acquire() -> EngineBackgroundTaskLease? {
        let lease = EngineBackgroundTaskLease()
        lease.identifier = UIApplication.shared.beginBackgroundTask(
            withName: "com.aapl.relaxin.engine",
            expirationHandler: { [weak lease] in
                lease?.expire()
            }
        )
        return lease.identifier == .invalid ? nil : lease
    }

    func end() {
        guard identifier != .invalid else { return }
        let identifier = identifier
        self.identifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }

    private func expire() {
        didExpire = true
        AppLog.error(EngineSession.self, "engine background task expired")
        end()
    }
}

private enum EngineBackgroundTaskFailure: Int {
    case unavailable = 1
    case expired

    func error(in resourceBundle: Bundle) -> NSError {
        let failureReason: String
        let recoverySuggestion: String
        let diagnostic: String
        switch self {
        case .unavailable:
            failureReason = String(
                localized: "iOS did not grant the required background execution assertion.",
                bundle: resourceBundle
            )
            recoverySuggestion = String(
                localized: "Close RELAXIN-X, reopen it, and try again.",
                bundle: resourceBundle
            )
            diagnostic = "stage=engine_start\nbackground_task=unavailable\nexploit_started=false"
        case .expired:
            failureReason = String(
                localized: "The background execution assertion expired before the engine returned.",
                bundle: resourceBundle
            )
            recoverySuggestion = String(
                localized: "Reboot the device before trying again.",
                bundle: resourceBundle
            )
            diagnostic = "stage=engine_run\nbackground_task=expired\nkernel_state_may_be_dirty=true"
        }
        return NSError(
            domain: "com.aapl.relaxin.background-task",
            code: rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    localized: "The engine could not remain active in the background.",
                    bundle: resourceBundle
                ),
                NSLocalizedFailureReasonErrorKey: failureReason,
                NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion,
                RLXEngineErrorUserInfoKey.diagnosticKey.rawValue: diagnostic,
            ]
        )
    }
}

private enum EngineRecoveryExecutorError: Error {
    case sessionReleased
}

private enum RuntimeAdmissionSessionError: LocalizedError {
    case resolutionUnavailable
    case invalidManifestResolution
    case resolutionChanged([String])
    case missingCapabilities([RuntimeCapability])
    case environmentBlocked(String)
    case backendExecutionUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .resolutionUnavailable:
            return "No verified runtime profile/backend resolution is available."
        case .invalidManifestResolution:
            return "The runtime manifest does not contain a valid profile/backend resolution identity."
        case .resolutionChanged(let reasons):
            return "The runtime profile/backend changed before execution: \(reasons.joined(separator: ", ")). Re-run the environment check."
        case .missingCapabilities(let capabilities):
            return "The selected runtime backend is missing required capabilities: \(capabilities.map(\.rawValue).sorted().joined(separator: ", "))."
        case .environmentBlocked(let reason):
            return reason
        case .backendExecutionUnavailable(let backendID):
            return "No executable runtime backend is registered for \(backendID)."
        }
    }
}

private enum TargetedRepairError: LocalizedError {
    case blocked([RepairFinding])
    case noVerifiedRepair
    case postConditionFailed(RepairAction, String)
    case finalState(JailbreakEnvironmentState)

    var errorDescription: String? {
        switch self {
        case .blocked(let findings):
            let details = findings.map(\.message).joined(separator: "; ")
            return details.isEmpty ? "The environment cannot be repaired automatically." : details
        case .noVerifiedRepair:
            return "No verified targeted repair is available for the current environment."
        case .postConditionFailed(_, let reason):
            return "A targeted repair did not satisfy its post-condition: \(reason)."
        case .finalState(let state):
            return "Repair completed, but the environment is not healthy: \(String(describing: state))."
        }
    }
}

private enum StealthCompatibilitySessionError: LocalizedError {
    case invalidBundleIdentifier
    case readBackMismatch(bundleIdentifier: String)

    var errorDescription: String? {
        switch self {
        case .invalidBundleIdentifier:
            return "The bundle identifier is not valid for a compatibility profile."
        case .readBackMismatch(let bundleIdentifier):
            return "The compatibility profile could not be verified for \(bundleIdentifier)."
        }
    }
}

private final class EngineRecoveryExecutor: RecoveryOperationExecuting {
    private let run: (RecoveryExecutionIntent) async throws -> Void

    init(run: @escaping (RecoveryExecutionIntent) async throws -> Void) {
        self.run = run
    }

    func execute(_ intent: RecoveryExecutionIntent) async throws {
        try await run(intent)
    }
}

@MainActor
final class EngineSession: ObservableObject {
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var output: [TerminalOutputLine] = []
    @Published private(set) var environmentSnapshot: EnvironmentSnapshot?
    @Published private(set) var environmentState: JailbreakEnvironmentState = .inspecting
    @Published private(set) var stealthHealth: StealthHealth = .suspended
    @Published private(set) var stealthProfiles: [AppStealthProfile] = []
    @Published private(set) var runtimeBackendPolicy: RuntimeBackendPolicy

    var environmentDiagnosticReport: EnvironmentDiagnosticReport? {
        guard let snapshot = environmentSnapshot else { return nil }
        let checkpointOutcome = EnvironmentCheckpointStore(
            fileURL: runtime.environmentRecoveryCheckpointURL
        ).loadOutcome(
            for: snapshot.fingerprint,
            generation: snapshot.generation,
            runtimeResolutionIdentity: snapshot.runtimeResolution?.checkpointIdentity
        )
        return EnvironmentDiagnosticReport.make(
            stage: environmentDiagnosticStage,
            state: environmentState,
            snapshot: snapshot,
            checkpointOutcome: checkpointOutcome
        )
    }

    func environmentDiagnosticJSON() -> String? {
        guard let report = environmentDiagnosticReport else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private var environmentDiagnosticStage: String {
        switch phase {
        case .idle: "idle"
        case .running: "engine_run"
        case .finished: "finished"
        case .failed: "failed"
        }
    }

    let runtime: RelaxinRuntime
    let postJailbreakSession: PostJailbreakSession
    private let engine: RLXEngine
    private let environmentInspector: EnvironmentInspector

    init(runtime: RelaxinRuntime) {
        self.runtime = runtime
        _runtimeBackendPolicy = Published(
            initialValue: RuntimeBackendPolicyStore(defaults: runtime.defaults).load()
        )
        let engine = RLXEngine(
            runtimeEnvironment: runtime.environment,
            additionalBootstrapPackageResourceNames:
            runtime.additionalBootstrapPackageResourceNames
        )
        self.engine = engine
        environmentInspector = EnvironmentInspector(
            provider: ProductionEnvironmentEvidenceProvider(
                runtime: runtime,
                postJailbreakController: engine.postJailbreakController
            )
        )
        postJailbreakSession = PostJailbreakSession(
            environment: runtime.postJailbreakEnvironment,
            controller: engine.postJailbreakController,
            reinstallSileo: { outputHandler in
                try await engine.perform(
                    action: .reinstallSileo,
                    arguments: nil,
                    output: outputHandler
                )
            }
        )
    }

    func reset() {
        guard case .idle = phase else { return }
        output.removeAll(keepingCapacity: true)
        postJailbreakSession.refreshAvailability()
        Task { await refreshEnvironment() }
    }

    func setRuntimeBackendExperimentalEnabled(_ enabled: Bool) async {
        let store = RuntimeBackendPolicyStore(defaults: runtime.defaults)
        store.setExperimentalEnabled(enabled)
        runtimeBackendPolicy = store.load()
        await refreshEnvironment()
    }

    func setPreferredRuntimeBackendID(_ backendID: String?) async {
        let store = RuntimeBackendPolicyStore(defaults: runtime.defaults)
        store.setPreferredBackendID(backendID)
        runtimeBackendPolicy = store.load()
        await refreshEnvironment()
    }

    func refreshEnvironment() async {
        environmentState = .inspecting
        let snapshot = await environmentInspector.inspect()
        let gate = CompatibilityGate.evaluate(snapshot)
        let state = EnvironmentStateResolver.resolve(snapshot: snapshot, gate: gate)
        environmentSnapshot = snapshot
        environmentState = state
        await refreshStealthCompatibility(snapshot: snapshot, state: state)
    }

    func setStealthProfileMode(
        _ mode: StealthProfileMode,
        bundleIdentifier: String
    ) async throws {
        let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StealthProfileIdentifier.isValid(bundleIdentifier) else {
            throw StealthCompatibilitySessionError.invalidBundleIdentifier
        }

        let snapshot = await environmentInspector.inspect()
        let gate = CompatibilityGate.evaluate(snapshot)
        let state = EnvironmentStateResolver.resolve(snapshot: snapshot, gate: gate)
        environmentSnapshot = snapshot
        environmentState = state
        if snapshot.runtimeResolution != nil {
            let stealthGate = CompatibilityGate.evaluate(
                snapshot,
                requirements: RuntimeOperationRequirements.stealth
            )
            if case .unsupported(let issue) = stealthGate.disposition {
                throw RuntimeAdmissionSessionError.environmentBlocked(issue.message)
            }
        }

        let resolver = StealthProfileResolver()
        let revalidator = StealthProfileRevalidator(resolver: resolver)
        let runtimeHealth = stealthRuntimeHealth(for: state)
        let requestedMode = resolver.hardRules.contains(bundleIdentifier) ? .developer : mode
        let store = StealthProfileStore(fileURL: runtime.stealthProfileURL)
        var profiles = try store.load()
        let index = profiles.firstIndex { $0.bundleIdentifier == bundleIdentifier }
        var profile = index.map { profiles[$0] }
            ?? AppStealthProfile(bundleIdentifier: bundleIdentifier)
        profile.mode = requestedMode
        profile.lastVerifiedGeneration = nil
        profile.lastVerifiedAt = nil

        if let index {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.bundleIdentifier < $1.bundleIdentifier }
        try store.save(profiles)
        stealthProfiles = profiles

        guard runtimeHealth == .healthy,
              let expected = revalidator.expectedCompatibility(
                  bundleID: bundleIdentifier,
                  userMode: requestedMode,
                  runtime: runtimeHealth
              )
        else {
            stealthHealth = StealthHealthInspector(resolver: resolver).inspect(
                runtime: runtimeHealth,
                profiles: profiles,
                generation: snapshot.generation
            )
            return
        }

        if !resolver.hardRules.contains(bundleIdentifier) {
            try await postJailbreakSession.setCompatibilityProfile(
                bundleIdentifier: bundleIdentifier,
                enabled: expected
            )
        }
        let actual = postJailbreakSession.compatibilityProfileEnabled(
            bundleIdentifier: bundleIdentifier
        )
        profile = revalidator.applyingReadback(
            to: profile,
            runtime: runtimeHealth,
            generation: snapshot.generation,
            actualCompatibilityEnabled: actual
        )
        guard profile.lastVerifiedGeneration == snapshot.generation else {
            throw StealthCompatibilitySessionError.readBackMismatch(
                bundleIdentifier: bundleIdentifier
            )
        }

        if let index = profiles.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            profiles[index] = profile
        }
        try store.save(profiles)
        stealthProfiles = profiles
        stealthHealth = StealthHealthInspector(resolver: resolver).inspect(
            runtime: runtimeHealth,
            profiles: profiles,
            generation: snapshot.generation
        )
    }

    func repairStealthProfile(bundleIdentifier: String) async throws {
        let profiles = try StealthProfileStore(fileURL: runtime.stealthProfileURL).load()
        guard let profile = profiles.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw StealthCompatibilitySessionError.invalidBundleIdentifier
        }
        try await setStealthProfileMode(profile.mode, bundleIdentifier: bundleIdentifier)
    }

    func start(
        manifest: [RLXEngineManifestKey: String],
        after initialDelay: Duration = .zero,
        onSuccess: @escaping () -> Void = {}
    ) {
        beginRun(
            stateDuringAdmission: nil,
            onSuccess: onSuccess
        ) { [self] in
            try await validateRuntimeAdmission(
                manifest: manifest,
                requirements: runtimeRequirementsForEngineManifest(manifest)
            )
            try await executeEngineRun(manifest: manifest, after: initialDelay)
        }
    }

    func startTargetedRepair(
        onSuccess: @escaping () -> Void = {}
    ) {
        beginRun(
            stateDuringAdmission: nil,
            onSuccess: onSuccess
        ) { [weak self] in
            guard let self else { throw EngineRecoveryExecutorError.sessionReleased }

            let initialSnapshot = await self.environmentInspector.inspect()
            let initialGate = CompatibilityGate.evaluate(initialSnapshot)
            let initialState = EnvironmentStateResolver.resolve(
                snapshot: initialSnapshot,
                gate: initialGate
            )
            let admission = EnvironmentRecoveryCoordinator(
                inspector: self.environmentInspector,
                executor: EngineRecoveryExecutor { _ in },
                checkpointStore: nil
            )
            try admission.admit(.repairEnvironment, state: initialState)

            let repairConfiguration = JailbreakConfiguration(defaults: runtime.defaults)
            let desiredPackageManagers = Set(
                repairConfiguration.packageManagers.selected.map { manager in
                    switch manager {
                    case .sileo: RepairPackageManager.sileo
                    case .zebra: RepairPackageManager.zebra
                    }
                }
            )
            let plan = RepairPlan.derive(
                from: initialSnapshot,
                desiredPackageManagers: desiredPackageManagers
            )
            guard plan.blockingFindings.isEmpty else {
                throw TargetedRepairError.blocked(plan.blockingFindings)
            }
            guard plan.isActionable else {
                throw TargetedRepairError.noVerifiedRepair
            }
            if initialSnapshot.runtimeResolution != nil {
                let repairGate = CompatibilityGate.evaluate(
                    initialSnapshot,
                    requirements: RuntimeOperationRequirements.repair(packageManager: true)
                )
                if case .unsupported(let issue) = repairGate.disposition {
                    throw RuntimeAdmissionSessionError.environmentBlocked(issue.message)
                }
            }

            let verifier = PostConditionVerifier()
            for action in plan.actions {
                try await self.executeTargetedRepair(action)
                let freshSnapshot = await self.environmentInspector.inspect()
                let verification = verifier.verifyRepair(action, snapshot: freshSnapshot)
                guard case .verified = verification else {
                    let reason: String
                    if case .failed(let failureReason) = verification {
                        reason = failureReason
                    } else {
                        reason = "unverified_repair"
                    }
                    throw TargetedRepairError.postConditionFailed(action, reason)
                }
            }

            // Fresh final inspection is the success condition for targeted repair.
            let finalSnapshot = await self.environmentInspector.inspect()
            let finalGate = CompatibilityGate.evaluate(finalSnapshot)
            let finalState = EnvironmentStateResolver.resolve(
                snapshot: finalSnapshot,
                gate: finalGate
            )
            guard finalState == .activeHealthy else {
                throw TargetedRepairError.finalState(finalState)
            }
            self.environmentSnapshot = finalSnapshot
            self.environmentState = finalState
            self.postJailbreakSession.refreshAvailability()
        }
    }

    func startRecovery(
        operation: RecoveryOperation,
        manifest: [RLXEngineManifestKey: String],
        after initialDelay: Duration = .zero,
        onSuccess: @escaping () -> Void = {}
    ) {
        let admissionState: JailbreakEnvironmentState? = operation == .restoreEnvironment
            ? .activating
            : nil
        beginRun(
            stateDuringAdmission: admissionState,
            onSuccess: onSuccess
        ) { [weak self] in
            guard let self else { throw EngineRecoveryExecutorError.sessionReleased }
            let executor = EngineRecoveryExecutor { [weak self] intent in
                guard let self else { throw EngineRecoveryExecutorError.sessionReleased }
                var recoveryManifest = manifest
                if intent.bootstrapStrategy == .reuseExisting {
                    recoveryManifest[.bootstrapRestoreModeKey] = "existing-required"
                }
                try await self.validateRuntimeAdmission(
                    manifest: recoveryManifest,
                    requirements: RuntimeOperationRequirements.restore
                )
                try await self.executeEngineRun(
                    manifest: recoveryManifest,
                    after: initialDelay
                )
            }
            let checkpointStore = EnvironmentCheckpointStore(
                fileURL: runtime.environmentRecoveryCheckpointURL
            )
            let coordinator = EnvironmentRecoveryCoordinator(
                inspector: self.environmentInspector,
                executor: executor,
                checkpointStore: checkpointStore,
                stealthRevalidation: { [weak self] snapshot in
                    guard let self else { return }
                    await self.revalidateStealth(snapshot: snapshot)
                }
            )
            try await coordinator.start(operation)
        }
    }

    private func validateRuntimeAdmission(
        manifest: [RLXEngineManifestKey: String],
        requirements: Set<RuntimeCapability>
    ) async throws {
        guard let selectedIdentity = runtimeResolutionIdentity(from: manifest) else {
            throw RuntimeAdmissionSessionError.invalidManifestResolution
        }
        let freshSnapshot = await environmentInspector.inspect()
        environmentSnapshot = freshSnapshot
        let freshGate = CompatibilityGate.evaluate(freshSnapshot, requirements: requirements)
        if case .unsupported(let issue) = freshGate.disposition {
            throw RuntimeAdmissionSessionError.environmentBlocked(issue.message)
        }
        guard let freshResolution = freshSnapshot.runtimeResolution else {
            throw RuntimeAdmissionSessionError.resolutionUnavailable
        }
        switch RuntimeExecutionAdmission.validate(
            selectedIdentity: selectedIdentity,
            freshResolution: freshResolution,
            requirements: requirements
        ) {
        case .admitted:
            return
        case .resolutionUnavailable:
            throw RuntimeAdmissionSessionError.resolutionUnavailable
        case .resolutionChanged(let reasons):
            throw RuntimeAdmissionSessionError.resolutionChanged(reasons)
        case .missingCapabilities(let capabilities):
            throw RuntimeAdmissionSessionError.missingCapabilities(capabilities)
        }
    }

    private func runtimeResolutionIdentity(
        from manifest: [RLXEngineManifestKey: String]
    ) -> RuntimeResolutionIdentity? {
        guard let profileID = manifest[.runtimeProfileIDKey], !profileID.isEmpty,
              let backendID = manifest[.runtimeBackendIDKey], !backendID.isEmpty,
              let backendGenerationText = manifest[.runtimeBackendGenerationKey],
              let backendGeneration = Int(backendGenerationText), backendGeneration > 0,
              let resolutionGenerationText = manifest[.runtimeResolutionGenerationKey],
              let resolutionGeneration = Int(resolutionGenerationText), resolutionGeneration > 0
        else { return nil }
        return RuntimeResolutionIdentity(
            profileID: profileID,
            backendID: backendID,
            backendGeneration: backendGeneration,
            resolutionGeneration: resolutionGeneration
        )
    }

    private func runtimeRequirementsForEngineManifest(
        _ manifest: [RLXEngineManifestKey: String]
    ) -> Set<RuntimeCapability> {
        if manifest[.removeJailbreakEnabledKey] == "true" {
            return [.verifyRuntime, .verifyBootstrap]
        }
        let packageManagerSelected = manifest[.installSileoEnabledKey] == "true"
            || manifest[.installZebraEnabledKey] == "true"
        return RuntimeOperationRequirements.freshInstall(
            packageManagerSelected: packageManagerSelected
        )
    }

    private func executeTargetedRepair(_ action: RepairAction) async throws {
        let outputHandler: (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.output.append(
                    TerminalOutputLine(label: message, status: .info)
                )
            }
        }

        switch action {
        case .repairSileo:
            try await engine.perform(
                action: .reinstallSileo,
                arguments: nil,
                output: outputHandler
            )
        case .repairZebra:
            let package = try await ZebraPackagePreflight(
                cacheDirectory: runtime.cacheDirectory
            ).prepare()
            try await engine.perform(
                action: .reinstallZebra,
                arguments: [.packagePathKey: package.path],
                output: outputHandler
            )
        case .repairPackageSources(let manager):
            try await engine.perform(
                action: .repairPackageSources,
                arguments: [.packageManagerKey: manager.rawValue],
                output: outputHandler
            )
        case .repairAppRegistration:
            try await engine.perform(
                action: .refreshJailbreakApps,
                arguments: nil,
                output: outputHandler
            )
        }
    }

    private func beginRun(
        stateDuringAdmission: JailbreakEnvironmentState?,
        onSuccess: @escaping () -> Void,
        operation: @escaping () async throws -> Void
    ) {
        guard case .idle = phase else { return }
        output.removeAll(keepingCapacity: true)
        phase = .running
        if let stateDuringAdmission {
            environmentState = stateDuringAdmission
        }
        let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        Task { [self] in
            defer {
                UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
            }
            do {
                try await operation()
                phase = .finished
                onSuccess()
            } catch {
                await refreshEnvironment()
                recordFailure(error)
            }
        }
    }

    private func executeEngineRun(
        manifest: [RLXEngineManifestKey: String],
        after initialDelay: Duration
    ) async throws {
        try await Task.sleep(for: initialDelay)
        guard let backgroundTask = EngineBackgroundTaskLease.acquire() else {
            throw EngineBackgroundTaskFailure.unavailable.error(
                in: runtime.resourceBundle
            )
        }
        defer {
            backgroundTask.end()
        }

        AppLog.setEngineOutputHandler { [weak self] message in
            Task { @MainActor [weak self] in
                self?.recordEngineOutput(message)
            }
        }
        defer {
            AppLog.setEngineOutputHandler(nil)
        }

        guard let backendID = manifest[.runtimeBackendIDKey],
              !backendID.isEmpty,
              let backend = RuntimeBackendExecutionRegistry.adapter(
                  for: backendID,
                  engine: engine
              )
        else {
            throw RuntimeAdmissionSessionError.backendExecutionUnavailable(
                manifest[.runtimeBackendIDKey] ?? "unknown"
            )
        }

        try await backend.execute(manifest: manifest) { update in
            self.recordTaskUpdate(update)
        }
        guard !backgroundTask.didExpire else {
            throw EngineBackgroundTaskFailure.expired.error(
                in: runtime.resourceBundle
            )
        }
        postJailbreakSession.refreshAvailability()
        await refreshEnvironment()
    }

    private func revalidateStealth(snapshot: EnvironmentSnapshot) async {
        let gate = CompatibilityGate.evaluate(snapshot)
        let state = EnvironmentStateResolver.resolve(snapshot: snapshot, gate: gate)
        await refreshStealthCompatibility(snapshot: snapshot, state: state)
    }

    private func refreshStealthCompatibility(
        snapshot: EnvironmentSnapshot,
        state: JailbreakEnvironmentState
    ) async {
        if let resolution = snapshot.runtimeResolution,
           !resolution.supports(RuntimeOperationRequirements.stealth)
        {
            stealthHealth = .suspended
            return
        }
        let store = StealthProfileStore(fileURL: runtime.stealthProfileURL)
        let resolver = StealthProfileResolver()
        let revalidator = StealthProfileRevalidator(resolver: resolver)
        let runtimeHealth = stealthRuntimeHealth(for: state)

        do {
            let loaded = try store.load()
            var profiles = StealthProfileStore.invalidatingVerification(
                in: loaded,
                for: snapshot.generation
            )

            if runtimeHealth == .healthy {
                profiles = profiles.map { profile in
                    guard revalidator.expectedCompatibility(
                        bundleID: profile.bundleIdentifier,
                        userMode: profile.mode,
                        runtime: runtimeHealth
                    ) != nil else {
                        var unresolved = profile
                        unresolved.lastVerifiedGeneration = nil
                        unresolved.lastVerifiedAt = nil
                        return unresolved
                    }
                    let actual = postJailbreakSession.compatibilityProfileEnabled(
                        bundleIdentifier: profile.bundleIdentifier
                    )
                    return revalidator.applyingReadback(
                        to: profile,
                        runtime: runtimeHealth,
                        generation: snapshot.generation,
                        actualCompatibilityEnabled: actual
                    )
                }
            }

            if profiles != loaded {
                try store.save(profiles)
            }
            stealthProfiles = profiles
            stealthHealth = StealthHealthInspector(resolver: resolver).inspect(
                runtime: runtimeHealth,
                profiles: profiles,
                generation: snapshot.generation
            )
        } catch {
            AppLog.error(Self.self, "Stealth Compatibility profile store error: \(error)")
            stealthHealth = StealthHealth(
                filesystemIsolation: .degraded(reason: "profile_store_error"),
                environmentSanitization: .needsVerification,
                packageManagerIsolation: .needsVerification,
                temporaryState: .clean,
                profileMapping: .degraded(reason: "profile_store_error"),
                overall: .degraded,
                affectedBundleIdentifiers: stealthProfiles.map(\.bundleIdentifier).sorted()
            )
        }
    }

    private func stealthRuntimeHealth(
        for state: JailbreakEnvironmentState
    ) -> StealthRuntimeHealth {
        switch state {
        case .activeHealthy:
            return .healthy
        case .activeDegraded:
            return .degraded
        case .installedInactive, .clean, .unsupported, .conflicting:
            return .inactive
        case .inspecting, .activating, .repairRequired:
            return .unknown
        }
    }

    func recordTaskUpdate(_ update: RLXEngineTaskUpdate) {
        let taskIdentifier = Int(update.stage.rawValue)
        if let index = output.firstIndex(where: { $0.taskIdentifier == taskIdentifier }) {
            output[index] = .task(update, details: output[index].details)
        } else {
            output.append(.task(update))
        }
    }

    func recordEngineOutput(_ message: String) {
        guard case .running = phase,
              let index = output.lastIndex(where: { $0.status == .running })
        else {
            return
        }

        let line = output[index]
        if let position = line.position,
           let count = line.count,
           message == "[\(position)/\(count)] \(line.label)"
        {
            return
        }
        output[index] = line.appendingDetails(from: message)
    }

    func recordFailure(_ error: Error) {
        let error = error as NSError
        let failure = Failure(report: makeFailureReport(for: error))
        phase = .failed(failure)
        AppLog.error(Self.self, failure.report)
    }
}
