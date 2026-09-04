import Foundation

private struct ParsedRuntimeVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let raw = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !raw.isEmpty, raw.count <= 4 else { return nil }
        var parsed: [Int] = []
        for item in raw {
            guard !item.isEmpty, let number = Int(item), number >= 0 else { return nil }
            parsed.append(number)
        }
        self.components = parsed
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return l < r }
        }
        return false
    }
}

enum RuntimeOSConstraint: Equatable, Hashable, Sendable {
    case versionRange(minimum: String, maximum: String)
    case exactVersions(Set<String>)

    func matches(_ version: String) -> Bool {
        switch self {
        case let .versionRange(minimum, maximum):
            guard let current = ParsedRuntimeVersion(version),
                  let lower = ParsedRuntimeVersion(minimum),
                  let upper = ParsedRuntimeVersion(maximum)
            else { return false }
            return current >= lower && current <= upper
        case let .exactVersions(versions):
            return versions.contains(version)
        }
    }
}

enum RuntimeRecoveryPolicy: String, Codable, Hashable, Sendable {
    case allowed
    case disabled
}

struct RuntimeProfile: Equatable, Hashable, Sendable {
    let id: String
    let displayName: String
    let osConstraint: RuntimeOSConstraint
    let exactBuilds: Set<String>
    let hardwareClasses: Set<HardwareExecutionClass>
    let requiredArchitecture: String
    let requiredBackendCapabilities: Set<RuntimeCapability>
    let optionalCapabilities: Set<RuntimeCapability>
    let bootstrapGeneration: String
    let minimumEnvironmentSchema: Int
    let recoveryPolicy: RuntimeRecoveryPolicy
    let maturityFloor: BackendMaturity
    let baselineID: String?
    let hardwareSupportIDs: Set<String>
    let minimumBackendGeneration: Int
    let requiredBaselineIntegrity: Set<BaselineIntegrityRequirement>

    init(
        id: String,
        displayName: String,
        osConstraint: RuntimeOSConstraint,
        exactBuilds: Set<String>,
        hardwareClasses: Set<HardwareExecutionClass>,
        requiredArchitecture: String,
        requiredBackendCapabilities: Set<RuntimeCapability>,
        optionalCapabilities: Set<RuntimeCapability>,
        bootstrapGeneration: String,
        minimumEnvironmentSchema: Int,
        recoveryPolicy: RuntimeRecoveryPolicy,
        maturityFloor: BackendMaturity,
        baselineID: String? = nil,
        hardwareSupportIDs: Set<String> = [],
        minimumBackendGeneration: Int = 1,
        requiredBaselineIntegrity: Set<BaselineIntegrityRequirement> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.osConstraint = osConstraint
        self.exactBuilds = exactBuilds
        self.hardwareClasses = hardwareClasses
        self.requiredArchitecture = requiredArchitecture
        self.requiredBackendCapabilities = requiredBackendCapabilities
        self.optionalCapabilities = optionalCapabilities
        self.bootstrapGeneration = bootstrapGeneration
        self.minimumEnvironmentSchema = minimumEnvironmentSchema
        self.recoveryPolicy = recoveryPolicy
        self.maturityFloor = maturityFloor
        self.baselineID = baselineID
        self.hardwareSupportIDs = hardwareSupportIDs.isEmpty
            ? Set(hardwareClasses.map(\.rawValue))
            : hardwareSupportIDs
        self.minimumBackendGeneration = minimumBackendGeneration
        self.requiredBaselineIntegrity = requiredBaselineIntegrity
    }

    func matches(_ environment: RuntimeEnvironment) -> Bool {
        guard osConstraint.matches(environment.osVersion),
              environment.environmentSchema >= minimumEnvironmentSchema,
              environment.architecture == requiredArchitecture
        else { return false }

        if !hardwareSupportIDs.isEmpty {
            guard let supportID = environment.hardwareSupportID,
                  hardwareSupportIDs.contains(supportID)
            else { return false }
        } else {
            guard let hardware = environment.hardwareExecutionClass,
                  hardwareClasses.contains(hardware)
            else { return false }
        }

        if let baselineID {
            guard environment.upstreamBaselineID == baselineID else { return false }
        }
        return exactBuilds.isEmpty || exactBuilds.contains(environment.osBuild)
    }

    func exactBuildMatch(_ environment: RuntimeEnvironment) -> Bool {
        !exactBuilds.isEmpty && exactBuilds.contains(environment.osBuild)
    }
}
