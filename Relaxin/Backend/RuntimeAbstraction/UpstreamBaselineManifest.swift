import Foundation

struct UpstreamBaselineManifest: Codable, Equatable, Hashable, Sendable {
    let id: String
    let upstreamProduct: String
    let upstreamVersion: String
    let releaseSHA256: String
    let kernelOffsetGeneration: String
    let kernelOffsetSHA256: String
    let bootstrapGeneration: String
    let bootstrapSHA256: String
    let baseBinGeneration: String
    let baseBinSHA256: String
    let minimumOSVersion: String
    let maximumOSVersion: String
    let supportedBuilds: Set<String>
    let hardwareSupportSet: Set<String>
    let requiredCapabilities: Set<String>
    let resourceDigests: [String: String]
    let manifestSchema: Int
}
