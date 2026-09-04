import Foundation
import RelaxinEngine

/// Immutable live target identity collected immediately before an engine run.
/// Product support is resolved by RuntimeProfileResolver, not by this type.
struct JailbreakTarget {
    enum ConfirmationError: Error {
        case simulator
        case missingDeviceIdentifier
        case missingBuild
        case missingCPUFamily
        case unsupportedSoC(UInt32)
        case missingRuntimeResolution

        func localizedDescription(in resourceBundle: Bundle) -> String {
            switch self {
            case .simulator:
                String(
                    localized: "The jailbreak target must be a physical iPhone or iPad.",
                    bundle: resourceBundle
                )
            case .missingDeviceIdentifier:
                String(
                    localized: "The exact device identifier could not be read.",
                    bundle: resourceBundle
                )
            case .missingBuild:
                String(
                    localized: "The exact iOS build number could not be read.",
                    bundle: resourceBundle
                )
            case .missingCPUFamily:
                String(
                    localized: "The device CPU family could not be read.",
                    bundle: resourceBundle
                )
            case let .unsupportedSoC(cpuFamily):
                String(
                    format: String(
                        localized: "CPU family %@ does not have a supported runtime profile.",
                        bundle: resourceBundle
                    ),
                    JailbreakTarget.hex(cpuFamily)
                )
            case .missingRuntimeResolution:
                String(
                    localized: "A verified runtime profile and backend could not be resolved.",
                    bundle: resourceBundle
                )
            }
        }
    }

    static let current = JailbreakTarget(
        deviceIdentifier: DeviceInfo.modelIdentifier,
        cpuFamily: DeviceInfo.cpuFamily,
        osVersion: DeviceInfo.osVersion,
        osBuild: DeviceInfo.osBuild,
        isSimulator: {
            #if targetEnvironment(simulator)
                true
            #else
                false
            #endif
        }()
    )

    let deviceIdentifier: String
    let cpuFamily: UInt32?
    let osVersion: String
    let osBuild: String?
    let isSimulator: Bool

    var hardwareExecutionClass: HardwareExecutionClass? {
        cpuFamily.flatMap(HardwareExecutionClass.init(cpuFamily:))
    }

    var socDescription: String {
        guard let cpuFamily else { return "unavailable" }
        let family = Self.hex(cpuFamily)
        guard let hardwareExecutionClass else { return family }
        return "\(hardwareExecutionClass.soc) (\(family))"
    }

    var buildDescription: String {
        osBuild ?? "unavailable"
    }

    var hardwareExecutionClassDescription: String {
        hardwareExecutionClass?.rawValue ?? "unavailable"
    }

    var logDescription: String {
        "device=\(deviceIdentifier) soc=\(socDescription) ios=\(osVersion) build=\(buildDescription) hardware_class=\(hardwareExecutionClassDescription)"
    }

    /// Identity-only legacy manifest retained for non-execution diagnostics.
    func confirmedManifest() throws -> [RLXEngineManifestKey: String] {
        try identityManifest()
    }

    func manifest(resolution: RuntimeResolution) throws -> [RLXEngineManifestKey: String] {
        guard let profileID = resolution.profileID,
              let backendID = resolution.backendID,
              let backendGeneration = resolution.backendGeneration,
              resolution.supportLevel != .unsupported
        else {
            throw ConfirmationError.missingRuntimeResolution
        }
        var manifest = try identityManifest()
        manifest[.runtimeProfileIDKey] = profileID
        manifest[.runtimeBackendIDKey] = backendID
        manifest[.runtimeBackendGenerationKey] = String(backendGeneration)
        manifest[.runtimeResolutionGenerationKey] = String(resolution.resolutionGeneration)
        manifest[.hardwareExecutionClassKey] = hardwareExecutionClassDescription
        manifest[.runtimeSupportLevelKey] = resolution.supportLevel.rawValue
        return manifest
    }

    private func identityManifest() throws -> [RLXEngineManifestKey: String] {
        if isSimulator {
            throw ConfirmationError.simulator
        }
        guard !deviceIdentifier.isEmpty else {
            throw ConfirmationError.missingDeviceIdentifier
        }
        guard let cpuFamily else {
            throw ConfirmationError.missingCPUFamily
        }
        guard let hardwareExecutionClass else {
            throw ConfirmationError.unsupportedSoC(cpuFamily)
        }
        guard let osBuild, !osBuild.isEmpty else {
            throw ConfirmationError.missingBuild
        }

        return [
            .targetDeviceIdentifierKey: deviceIdentifier,
            .targetSoCKey: hardwareExecutionClass.soc,
            .targetCPUFamilyKey: Self.hex(cpuFamily),
            .targetOSVersionKey: osVersion,
            .targetOSBuildKey: osBuild,
            .runtimeProfileKey: hardwareExecutionClass.rawValue,
        ]
    }

    private static func hex(_ value: UInt32) -> String {
        String(format: "0x%08X", value)
    }
}
