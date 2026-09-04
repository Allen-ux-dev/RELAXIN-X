import Foundation

enum HardwareSupportStatus: String, Codable, Hashable, Sendable {
    case supported
    case experimental
    case recognized
    case unsupported
}

struct HardwareSupportDescriptor: Equatable, Hashable, Sendable {
    let id: String
    let displaySoC: String
    let cpuFamilies: Set<UInt32>
    let legacyExecutionClass: HardwareExecutionClass?
    let status: HardwareSupportStatus
    let minimumBackendGeneration: Int
    let requiredCapabilities: Set<RuntimeCapability>
    let requiredBaselineIntegrity: Set<BaselineIntegrityRequirement>
}
