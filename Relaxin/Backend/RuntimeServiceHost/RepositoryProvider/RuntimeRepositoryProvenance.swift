import Foundation

enum RuntimeRepositoryTrust: String, Codable, Hashable, Sendable {
    case verified
    case unverified
    case rejected
}

struct RuntimeRepositoryProvenance: Equatable, Hashable, Codable, Sendable {
    let distribution: String
    let sourceIdentifier: String
    let iconURL: String?
    let depictionURL: String?
}
