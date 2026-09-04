import Foundation

struct RuntimeEnvironment: Equatable, Hashable, Sendable {
    let deviceIdentifier: String
    let cpuFamily: UInt32?
    let architecture: String
    let osVersion: String
    let osBuild: String
    let isSimulator: Bool
    let environmentSchema: Int
    let hasInstalledBootstrap: Bool
    let runtimeActive: Bool
    let upstreamBaselineID: String?
    let availableBaselineIntegrity: Set<BaselineIntegrityRequirement>

    init(
        deviceIdentifier: String,
        cpuFamily: UInt32?,
        architecture: String,
        osVersion: String,
        osBuild: String,
        isSimulator: Bool,
        environmentSchema: Int,
        hasInstalledBootstrap: Bool,
        runtimeActive: Bool,
        upstreamBaselineID: String? = nil,
        availableBaselineIntegrity: Set<BaselineIntegrityRequirement> = []
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.cpuFamily = cpuFamily
        self.architecture = architecture
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.isSimulator = isSimulator
        self.environmentSchema = environmentSchema
        self.hasInstalledBootstrap = hasInstalledBootstrap
        self.runtimeActive = runtimeActive
        self.upstreamBaselineID = upstreamBaselineID
        self.availableBaselineIntegrity = availableBaselineIntegrity
    }

    var hardwareExecutionClass: HardwareExecutionClass? {
        cpuFamily.flatMap(HardwareExecutionClass.init(cpuFamily:))
    }

    var hardwareSupportDescriptor: HardwareSupportDescriptor? {
        cpuFamily.flatMap(HardwareSupportRegistry.resolve(cpuFamily:))
    }

    var hardwareSupportID: String? {
        hardwareSupportDescriptor?.id
    }
}
