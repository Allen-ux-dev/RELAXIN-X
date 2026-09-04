import Foundation

struct RuntimeBackendPolicy: Equatable, Hashable, Sendable {
    static let recommended = RuntimeBackendPolicy(experimentalEnabled: false, preferredBackendID: nil)

    let experimentalEnabled: Bool
    let preferredBackendID: String?
}
