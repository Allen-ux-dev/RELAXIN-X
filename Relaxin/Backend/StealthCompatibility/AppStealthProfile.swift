import Foundation

// Compatibility/privacy boundary: these profiles reduce accidental jailbreak-
// environment exposure for ordinary-app compatibility. They do not bypass
// security controls, falsify device security state, or install global syscall
// interception/spoofing behavior.
enum StealthProfileMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case automatic
    case compatibility
    case developer
    case disabled
    case needsReview
}

struct AppStealthProfile: Codable, Equatable, Identifiable, Sendable {
    let bundleIdentifier: String
    var mode: StealthProfileMode
    var filesystemIsolation: Bool
    var environmentSanitization: Bool
    var packageManagerIsolation: Bool
    var temporaryStateCleanup: Bool
    var loggingPrivacy: Bool
    var lastVerifiedGeneration: EnvironmentGeneration?
    var lastVerifiedAt: Date?

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        mode: StealthProfileMode = .automatic,
        filesystemIsolation: Bool = true,
        environmentSanitization: Bool = true,
        packageManagerIsolation: Bool = true,
        temporaryStateCleanup: Bool = true,
        loggingPrivacy: Bool = true,
        lastVerifiedGeneration: EnvironmentGeneration? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.mode = mode
        self.filesystemIsolation = filesystemIsolation
        self.environmentSanitization = environmentSanitization
        self.packageManagerIsolation = packageManagerIsolation
        self.temporaryStateCleanup = temporaryStateCleanup
        self.loggingPrivacy = loggingPrivacy
        self.lastVerifiedGeneration = lastVerifiedGeneration
        self.lastVerifiedAt = lastVerifiedAt
    }
}

enum StealthProfileIdentifier {
    static func isValid(_ bundleIdentifier: String) -> Bool {
        guard !bundleIdentifier.isEmpty, bundleIdentifier.utf8.count <= 255 else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-")
        )
        return bundleIdentifier.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
