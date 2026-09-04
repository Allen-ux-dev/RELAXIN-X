import Foundation

struct EnvironmentCheckpoint: Codable, Equatable, Sendable {
    let operation: RecoveryOperation
    let completedStages: [RecoveryStage]
    let fingerprint: EnvironmentFingerprint
    let generation: EnvironmentGeneration
    let runtimeResolutionIdentity: RuntimeResolutionIdentity?
    let verifiedAt: Date

    init(
        operation: RecoveryOperation,
        completedStages: [RecoveryStage],
        fingerprint: EnvironmentFingerprint,
        generation: EnvironmentGeneration,
        runtimeResolutionIdentity: RuntimeResolutionIdentity? = nil,
        verifiedAt: Date
    ) {
        self.operation = operation
        self.completedStages = completedStages
        self.fingerprint = fingerprint
        self.generation = generation
        self.runtimeResolutionIdentity = runtimeResolutionIdentity
        self.verifiedAt = verifiedAt
    }
}

struct EnvironmentCheckpointLoadOutcome: Equatable, Sendable {
    let checkpoint: EnvironmentCheckpoint?
    let diagnostic: String?
}

struct EnvironmentCheckpointStore: Sendable {
    let fileURL: URL

    func save(_ checkpoint: EnvironmentCheckpoint) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL, options: [.atomic])
    }

    func loadValidated(
        for fingerprint: EnvironmentFingerprint,
        generation: EnvironmentGeneration,
        runtimeResolutionIdentity: RuntimeResolutionIdentity? = nil
    ) -> EnvironmentCheckpoint? {
        loadOutcome(
            for: fingerprint,
            generation: generation,
            runtimeResolutionIdentity: runtimeResolutionIdentity
        ).checkpoint
    }

    func loadOutcome(
        for fingerprint: EnvironmentFingerprint,
        generation: EnvironmentGeneration,
        runtimeResolutionIdentity: RuntimeResolutionIdentity? = nil
    ) -> EnvironmentCheckpointLoadOutcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return EnvironmentCheckpointLoadOutcome(
                checkpoint: nil,
                diagnostic: "checkpoint_missing"
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let checkpoint: EnvironmentCheckpoint
            do {
                checkpoint = try JSONDecoder().decode(EnvironmentCheckpoint.self, from: data)
            } catch {
                return EnvironmentCheckpointLoadOutcome(
                    checkpoint: nil,
                    diagnostic: "checkpoint_decode_failed: \(error.localizedDescription)"
                )
            }

            let invalidation = StaleStateInvalidator.compare(
                previousGeneration: checkpoint.generation,
                currentGeneration: generation,
                previousFingerprint: checkpoint.fingerprint,
                currentFingerprint: fingerprint
            )
            if invalidation.invalidateCheckpoint {
                let reason = invalidation.reasons.isEmpty
                    ? "unspecified_identity_change"
                    : invalidation.reasons.joined(separator: ",")
                return EnvironmentCheckpointLoadOutcome(
                    checkpoint: nil,
                    diagnostic: "checkpoint_stale: \(reason)"
                )
            }

            if let currentIdentity = runtimeResolutionIdentity {
                guard let previousIdentity = checkpoint.runtimeResolutionIdentity else {
                    return EnvironmentCheckpointLoadOutcome(
                        checkpoint: nil,
                        diagnostic: "checkpoint_stale: runtime_resolution_missing"
                    )
                }
                let reasons = previousIdentity.mismatchReasons(comparedWith: currentIdentity)
                if !reasons.isEmpty {
                    return EnvironmentCheckpointLoadOutcome(
                        checkpoint: nil,
                        diagnostic: "checkpoint_stale: \(reasons.joined(separator: ","))"
                    )
                }
            }

            return EnvironmentCheckpointLoadOutcome(
                checkpoint: checkpoint,
                diagnostic: nil
            )
        } catch {
            return EnvironmentCheckpointLoadOutcome(
                checkpoint: nil,
                diagnostic: "checkpoint_read_failed: \(error.localizedDescription)"
            )
        }
    }
}
