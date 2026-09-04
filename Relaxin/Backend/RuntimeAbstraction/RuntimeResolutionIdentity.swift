import Foundation

struct RuntimeResolutionIdentity: Codable, Equatable, Hashable, Sendable {
    let profileID: String
    let baselineID: String?
    let backendID: String
    let backendGeneration: Int
    let resolutionGeneration: Int

    init(
        profileID: String,
        baselineID: String? = nil,
        backendID: String,
        backendGeneration: Int,
        resolutionGeneration: Int
    ) {
        self.profileID = profileID
        self.baselineID = baselineID
        self.backendID = backendID
        self.backendGeneration = backendGeneration
        self.resolutionGeneration = resolutionGeneration
    }

    func mismatchReasons(comparedWith current: RuntimeResolutionIdentity) -> [String] {
        var reasons: [String] = []
        if profileID != current.profileID { reasons.append("runtime_profile_changed") }
        if baselineID != current.baselineID { reasons.append("upstream_baseline_changed") }
        if backendID != current.backendID { reasons.append("runtime_backend_changed") }
        if backendGeneration != current.backendGeneration { reasons.append("runtime_backend_generation_changed") }
        if resolutionGeneration != current.resolutionGeneration { reasons.append("runtime_resolution_generation_changed") }
        return reasons
    }
}
