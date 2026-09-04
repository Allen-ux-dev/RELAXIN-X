import Foundation

struct StealthProfileRevalidator: Sendable {
    let resolver: StealthProfileResolver

    init(resolver: StealthProfileResolver = StealthProfileResolver()) {
        self.resolver = resolver
    }

    func expectedCompatibility(
        bundleID: String,
        userMode: StealthProfileMode,
        runtime: StealthRuntimeHealth
    ) -> Bool? {
        switch resolver.resolve(bundleID: bundleID, userMode: userMode, runtime: runtime) {
        case .compatibility:
            return true
        case .developer, .disabled:
            return false
        case .automatic, .needsReview:
            return nil
        }
    }

    func applyingReadback(
        to profile: AppStealthProfile,
        runtime: StealthRuntimeHealth,
        generation: EnvironmentGeneration,
        actualCompatibilityEnabled: Bool,
        verifiedAt: Date = Date()
    ) -> AppStealthProfile {
        var result = profile
        guard let expected = expectedCompatibility(
            bundleID: profile.bundleIdentifier,
            userMode: profile.mode,
            runtime: runtime
        ), expected == actualCompatibilityEnabled else {
            result.lastVerifiedGeneration = nil
            result.lastVerifiedAt = nil
            return result
        }
        result.lastVerifiedGeneration = generation
        result.lastVerifiedAt = verifiedAt
        return result
    }
}
