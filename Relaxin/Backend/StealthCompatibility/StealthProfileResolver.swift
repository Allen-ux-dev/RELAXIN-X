import Foundation

enum StealthRuntimeHealth: String, Codable, Equatable, Sendable {
    case healthy
    case inactive
    case degraded
    case unknown
}

struct StealthProfileResolver: Sendable {
    static let managementBundleIdentifiers: Set<String> = [
        "com.aapl.relaxin",
        "org.coolstar.SileoStore",
        "xyz.willy.Zebra",
        "com.roothide.manager",
    ]

    let hardRules: Set<String>

    init(hardRules: Set<String> = Self.managementBundleIdentifiers) {
        self.hardRules = hardRules
    }

    func resolve(
        bundleID: String,
        userMode: StealthProfileMode,
        runtime: StealthRuntimeHealth
    ) -> StealthProfileMode {
        if hardRules.contains(bundleID) {
            return .developer
        }

        switch userMode {
        case .developer, .disabled:
            return userMode
        case .automatic, .compatibility:
            return runtime == .healthy ? .compatibility : .needsReview
        case .needsReview:
            return .needsReview
        }
    }
}
