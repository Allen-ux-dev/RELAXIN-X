import Foundation

enum BaselineIntegrityRequirement: String, CaseIterable, Codable, Hashable, Sendable {
    case kernelProfilePresent
    case kernelcacheDigestPresent
    case sptmDigestPresent
    case txmDigestPresent
    case bootstrapDigestMatch
    case baseBinDigestMatch
}
