import Foundation

struct RuntimeBackendDescriptor: Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let maturity: BackendMaturity
    let supportedProfileIDs: Set<String>
    let capabilities: Set<RuntimeCapability>
    let hardwareClasses: Set<HardwareExecutionClass>
    let minimumEnvironmentSchema: Int
    let backendGeneration: Int
}
