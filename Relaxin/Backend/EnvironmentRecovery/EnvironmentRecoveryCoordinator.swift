import Foundation

protocol RecoveryOperationExecuting: AnyObject {
    func execute(_ intent: RecoveryExecutionIntent) async throws
}

enum RecoveryAdmissionError: Error, Equatable {
    case invalidState(operation: RecoveryOperation, state: JailbreakEnvironmentState)
}

enum RecoveryVerificationError: Error, Equatable {
    case postConditionFailed(stage: RecoveryStage, reason: String)
}

struct EnvironmentRecoveryCoordinator {
    let inspector: EnvironmentInspector
    let executor: any RecoveryOperationExecuting
    let checkpointStore: EnvironmentCheckpointStore?
    let verifier: PostConditionVerifier
    let stealthRevalidation: ((EnvironmentSnapshot) async -> Void)?

    init(
        inspector: EnvironmentInspector,
        executor: any RecoveryOperationExecuting,
        checkpointStore: EnvironmentCheckpointStore? = nil,
        verifier: PostConditionVerifier = PostConditionVerifier(),
        stealthRevalidation: ((EnvironmentSnapshot) async -> Void)? = nil
    ) {
        self.inspector = inspector
        self.executor = executor
        self.checkpointStore = checkpointStore
        self.verifier = verifier
        self.stealthRevalidation = stealthRevalidation
    }

    func start(_ operation: RecoveryOperation) async throws {
        let initialSnapshot = await inspector.inspect()
        let requirements = runtimeRequirements(for: operation, snapshot: initialSnapshot)
        let gate = CompatibilityGate.evaluate(initialSnapshot, requirements: requirements)
        let state = EnvironmentStateResolver.resolve(snapshot: initialSnapshot, gate: gate)
        try admit(operation, state: state)

        var completedStages = checkpointStore?
            .loadValidated(
                for: initialSnapshot.fingerprint,
                generation: initialSnapshot.generation,
                runtimeResolutionIdentity: initialSnapshot.runtimeResolution?.checkpointIdentity
            )?
            .completedStages ?? []

        // A persisted checkpoint is progress history, not proof that the current
        // runtime is still active. Every stage is freshly verified before it is
        // accepted during this invocation.
        try checkpointVerified(
            .preflight,
            snapshot: initialSnapshot,
            operation: operation,
            completedStages: &completedStages
        )
        try checkpointVerified(
            .prepare,
            snapshot: initialSnapshot,
            operation: operation,
            completedStages: &completedStages
        )

        try await executor.execute(.intent(for: operation))

        // The executor returning successfully is not the success condition.
        // Re-read live state and prove every externally visible post-condition.
        let finalSnapshot = await inspector.inspect()
        for stage in [
            RecoveryStage.execute,
            .bootstrap,
            .packageManager,
            .finalize,
            .verify,
        ] {
            try checkpointVerified(
                stage,
                snapshot: finalSnapshot,
                operation: operation,
                completedStages: &completedStages
            )
        }

        if operation == .restoreEnvironment {
            await stealthRevalidation?(finalSnapshot)
        }
    }


    private func runtimeRequirements(
        for operation: RecoveryOperation,
        snapshot: EnvironmentSnapshot
    ) -> Set<RuntimeCapability> {
        switch operation {
        case .freshInstall:
            return RuntimeOperationRequirements.freshInstall(packageManagerSelected: false)
        case .restoreEnvironment:
            return RuntimeOperationRequirements.restore
        case .repairEnvironment:
            return RuntimeOperationRequirements.repair(
                bootstrap: !snapshot.bootstrap.isValidRelaxin,
                packageManager: snapshot.packageManagers.hasDegradedComponent
                    || !snapshot.packageManagers.hasInstalledComponent
            )
        }
    }

    func admit(_ operation: RecoveryOperation, state: JailbreakEnvironmentState) throws {
        switch (operation, state) {
        case (.freshInstall, .clean),
             (.restoreEnvironment, .installedInactive),
             (.repairEnvironment, .repairRequired),
             (.repairEnvironment, .activeDegraded):
            return
        default:
            throw RecoveryAdmissionError.invalidState(operation: operation, state: state)
        }
    }

    private func checkpointVerified(
        _ stage: RecoveryStage,
        snapshot: EnvironmentSnapshot,
        operation: RecoveryOperation,
        completedStages: inout [RecoveryStage]
    ) throws {
        let verification = verifier.verify(
            stage,
            operation: operation,
            snapshot: snapshot
        )
        guard case .verified = verification else {
            if case .failed(let reason) = verification {
                throw RecoveryVerificationError.postConditionFailed(
                    stage: stage,
                    reason: reason
                )
            }
            return
        }

        if !completedStages.contains(stage) {
            completedStages.append(stage)
        }
        guard let checkpointStore else { return }
        try checkpointStore.save(
            EnvironmentCheckpoint(
                operation: operation,
                completedStages: completedStages,
                fingerprint: snapshot.fingerprint,
                generation: snapshot.generation,
                runtimeResolutionIdentity: snapshot.runtimeResolution?.checkpointIdentity,
                verifiedAt: Date()
            )
        )
    }
}
