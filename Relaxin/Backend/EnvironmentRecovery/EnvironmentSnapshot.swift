import Foundation

struct EnvironmentIssue: Codable, Equatable, Hashable, Sendable {
    let code: String
    let message: String
}

struct TargetEvidence: Codable, Equatable, Sendable {
    let supported: Bool
    let reason: String?
}

struct RuntimeEvidence: Codable, Equatable, Sendable {
    let active: Bool
    let rootHideReportedJailbroken: Bool
    let processRuntimeActive: Bool
    let processIsPlatform: Bool
}

enum BootstrapEvidence: Codable, Equatable, Sendable {
    case absent
    case validRelaxin(identity: String)
    case incomplete(reason: String)
    case ambiguous(count: Int)

    var isValidRelaxin: Bool {
        if case .validRelaxin = self { return true }
        return false
    }

    var hasInstalledArtifacts: Bool {
        switch self {
        case .absent:
            return false
        case .validRelaxin, .incomplete, .ambiguous:
            return true
        }
    }
}

struct StorageEvidence: Codable, Equatable, Sendable {
    let freeBytes: UInt64
    let minimumRequiredBytes: UInt64

    var hasSufficientSpace: Bool {
        freeBytes >= minimumRequiredBytes
    }

    static let sufficient = StorageEvidence(
        freeBytes: UInt64.max,
        minimumRequiredBytes: 0
    )
}

enum PackageManagerComponentHealth: Codable, Equatable, Sendable {
    case notInstalled
    case healthy
    case degraded(reason: String)
    case repairRequired(reason: String)

    var isDegraded: Bool {
        switch self {
        case .degraded, .repairRequired:
            return true
        case .notInstalled, .healthy:
            return false
        }
    }

    var requiresRepair: Bool {
        if case .repairRequired = self { return true }
        return false
    }
}

struct PackageManagerEvidence: Codable, Equatable, Sendable {
    let sileo: PackageManagerComponentHealth
    let zebra: PackageManagerComponentHealth

    var hasDegradedComponent: Bool {
        sileo.isDegraded || zebra.isDegraded
    }

    var requiresRepair: Bool {
        sileo.requiresRepair || zebra.requiresRepair
    }

    var hasInstalledComponent: Bool {
        switch (sileo, zebra) {
        case (.notInstalled, .notInstalled):
            false
        default:
            true
        }
    }
}

enum HistoricalEnvironmentHint: String, Codable, Equatable, Sendable {
    case none
    case previouslyJailbroken
}

struct EnvironmentSnapshot: Equatable, Sendable {
    let target: TargetEvidence
    let runtime: RuntimeEvidence
    let bootstrap: BootstrapEvidence
    let storage: StorageEvidence
    let packageManagers: PackageManagerEvidence
    let conflicts: [EnvironmentIssue]
    let historicalHint: HistoricalEnvironmentHint
    let fingerprint: EnvironmentFingerprint
    let generation: EnvironmentGeneration
    let runtimeResolution: RuntimeResolution?
    let inspectedAt: Date

    init(
        target: TargetEvidence,
        runtime: RuntimeEvidence,
        bootstrap: BootstrapEvidence,
        storage: StorageEvidence,
        packageManagers: PackageManagerEvidence,
        conflicts: [EnvironmentIssue],
        historicalHint: HistoricalEnvironmentHint,
        fingerprint: EnvironmentFingerprint = .unknown,
        generation: EnvironmentGeneration = .baseline,
        runtimeResolution: RuntimeResolution? = nil,
        inspectedAt: Date
    ) {
        self.target = target
        self.runtime = runtime
        self.bootstrap = bootstrap
        self.storage = storage
        self.packageManagers = packageManagers
        self.conflicts = conflicts
        self.historicalHint = historicalHint
        self.fingerprint = fingerprint
        self.generation = generation
        self.runtimeResolution = runtimeResolution
        self.inspectedAt = inspectedAt
    }
}
