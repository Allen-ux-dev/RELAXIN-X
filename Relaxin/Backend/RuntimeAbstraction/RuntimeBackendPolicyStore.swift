import Foundation

struct RuntimeBackendPolicyStore {
    private enum Key {
        static let experimentalEnabled = "RuntimeBackendPolicy.experimentalEnabled"
        static let preferredBackendID = "RuntimeBackendPolicy.preferredBackendID"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> RuntimeBackendPolicy {
        let preferred = defaults.string(forKey: Key.preferredBackendID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return RuntimeBackendPolicy(
            experimentalEnabled: defaults.bool(forKey: Key.experimentalEnabled),
            preferredBackendID: preferred.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func setExperimentalEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.experimentalEnabled)
    }

    func setPreferredBackendID(_ backendID: String?) {
        let normalized = backendID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            defaults.set(normalized, forKey: Key.preferredBackendID)
        } else {
            defaults.removeObject(forKey: Key.preferredBackendID)
        }
    }
}
