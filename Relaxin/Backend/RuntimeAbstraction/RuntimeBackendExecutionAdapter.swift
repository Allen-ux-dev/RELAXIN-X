import Foundation
import RelaxinEngine

@MainActor
protocol RuntimeBackendExecutionAdapter {
    var backendID: String { get }

    func execute(
        manifest: [RLXEngineManifestKey: String],
        updateHandler: @escaping (RLXEngineTaskUpdate) -> Void
    ) async throws
}

@MainActor
struct LegacyRelaxinRuntimeExecutionAdapter: RuntimeBackendExecutionAdapter {
    let engine: RLXEngine

    var backendID: String {
        LegacyRelaxinRuntimeBackend.backendID
    }

    func execute(
        manifest: [RLXEngineManifestKey: String],
        updateHandler: @escaping (RLXEngineTaskUpdate) -> Void
    ) async throws {
        try await engine.run(manifest: manifest) { update in
            updateHandler(update)
        }
    }
}

@MainActor
enum RuntimeBackendExecutionRegistry {
    static func adapter(
        for backendID: String,
        engine: RLXEngine
    ) -> (any RuntimeBackendExecutionAdapter)? {
        switch backendID {
        case LegacyRelaxinRuntimeBackend.backendID:
            return LegacyRelaxinRuntimeExecutionAdapter(engine: engine)
        default:
            return nil
        }
    }
}
