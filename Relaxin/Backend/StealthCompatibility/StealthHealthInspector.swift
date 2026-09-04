import Foundation

enum StealthOverallHealth: String, Codable, Equatable, Sendable {
    case ready
    case suspended
    case degraded
    case needsVerification
}

enum StealthComponentHealth: Equatable, Sendable {
    case healthy
    case clean
    case valid
    case suspended
    case needsVerification
    case degraded(reason: String)
}

struct StealthHealth: Equatable, Sendable {
    let filesystemIsolation: StealthComponentHealth
    let environmentSanitization: StealthComponentHealth
    let packageManagerIsolation: StealthComponentHealth
    let temporaryState: StealthComponentHealth
    let profileMapping: StealthComponentHealth
    let overall: StealthOverallHealth
    let affectedBundleIdentifiers: [String]

    static let suspended = StealthHealth(
        filesystemIsolation: .suspended,
        environmentSanitization: .suspended,
        packageManagerIsolation: .suspended,
        temporaryState: .clean,
        profileMapping: .needsVerification,
        overall: .suspended,
        affectedBundleIdentifiers: []
    )
}

struct StealthHealthInspector: Sendable {
    let resolver: StealthProfileResolver

    init(resolver: StealthProfileResolver = StealthProfileResolver()) {
        self.resolver = resolver
    }

    func inspect(
        runtime: StealthRuntimeHealth,
        profiles: [AppStealthProfile],
        generation: EnvironmentGeneration
    ) -> StealthHealth {
        guard runtime == .healthy else {
            if runtime == .inactive {
                return .suspended
            }
            return StealthHealth(
                filesystemIsolation: .needsVerification,
                environmentSanitization: .needsVerification,
                packageManagerIsolation: .needsVerification,
                temporaryState: .clean,
                profileMapping: .needsVerification,
                overall: runtime == .degraded ? .degraded : .needsVerification,
                affectedBundleIdentifiers: profiles.map(\.bundleIdentifier).sorted()
            )
        }

        let stale = profiles.filter { profile in
            let effective = resolver.resolve(
                bundleID: profile.bundleIdentifier,
                userMode: profile.mode,
                runtime: runtime
            )
            if effective == .needsReview {
                return true
            }
            return profile.lastVerifiedGeneration != generation
        }
        let affected = stale.map(\.bundleIdentifier).sorted()
        guard affected.isEmpty else {
            return StealthHealth(
                filesystemIsolation: .needsVerification,
                environmentSanitization: .needsVerification,
                packageManagerIsolation: .needsVerification,
                temporaryState: .clean,
                profileMapping: .needsVerification,
                overall: .needsVerification,
                affectedBundleIdentifiers: affected
            )
        }

        return StealthHealth(
            filesystemIsolation: .healthy,
            environmentSanitization: .healthy,
            packageManagerIsolation: .healthy,
            temporaryState: .clean,
            profileMapping: .valid,
            overall: .ready,
            affectedBundleIdentifiers: []
        )
    }
}

enum StealthRepairAction: Equatable, Sendable {
    case revalidateProfile(bundleIdentifier: String)

    static let contractVocabulary = [
        "revalidateProfile",
    ]
}

struct StealthRepairPlan: Equatable, Sendable {
    let actions: [StealthRepairAction]

    static func derive(from health: StealthHealth) -> StealthRepairPlan {
        guard health.overall == .needsVerification || health.overall == .degraded else {
            return StealthRepairPlan(actions: [])
        }
        return StealthRepairPlan(
            actions: health.affectedBundleIdentifiers.map {
                .revalidateProfile(bundleIdentifier: $0)
            }
        )
    }
}
