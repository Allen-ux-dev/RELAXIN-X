import Foundation

protocol EnvironmentEvidenceProviding {
    func targetEvidence() async -> TargetEvidence
    func runtimeEvidence() async -> RuntimeEvidence
    func bootstrapEvidence() async -> BootstrapEvidence
    func storageEvidence() async -> StorageEvidence
    func packageManagerEvidence() async -> PackageManagerEvidence
    func conflictEvidence() async -> [EnvironmentIssue]
    func fingerprintEvidence() async -> EnvironmentFingerprint
    func generationEvidence() async -> EnvironmentGeneration
    func runtimeEnvironmentEvidence(runtime: RuntimeEvidence, bootstrap: BootstrapEvidence) async -> RuntimeEnvironment?
    func runtimeBackendPolicy() async -> RuntimeBackendPolicy
}

extension EnvironmentEvidenceProviding {
    func fingerprintEvidence() async -> EnvironmentFingerprint { .unknown }
    func generationEvidence() async -> EnvironmentGeneration { .baseline }
    func runtimeEnvironmentEvidence(runtime: RuntimeEvidence, bootstrap: BootstrapEvidence) async -> RuntimeEnvironment? { nil }
    func runtimeBackendPolicy() async -> RuntimeBackendPolicy {
        .recommended
    }
}

struct EnvironmentInspector {
    let provider: any EnvironmentEvidenceProviding

    func inspect() async -> EnvironmentSnapshot {
        // Keep inspection deterministic and side-effect free. Production evidence
        // adapters are read-only, so there is no reason to race them concurrently.
        let target = await provider.targetEvidence()
        let runtime = await provider.runtimeEvidence()
        let bootstrap = await provider.bootstrapEvidence()
        let storage = await provider.storageEvidence()
        let packages = await provider.packageManagerEvidence()
        let conflicts = await provider.conflictEvidence()
        let fingerprint = await provider.fingerprintEvidence()
        let generation = await provider.generationEvidence()
        let runtimeEnvironment = await provider.runtimeEnvironmentEvidence(runtime: runtime, bootstrap: bootstrap)
        let backendPolicy = await provider.runtimeBackendPolicy()
        let runtimeResolution = runtimeEnvironment.map { environment in
            RuntimeProfileResolver.resolve(
                environment: environment,
                profiles: RuntimeProfileRegistry.production,
                backends: RuntimeBackendRegistry.production,
                policy: backendPolicy
            )
        }

        return EnvironmentSnapshot(
            target: target,
            runtime: runtime,
            bootstrap: bootstrap,
            storage: storage,
            packageManagers: packages,
            conflicts: conflicts,
            historicalHint: .none,
            fingerprint: fingerprint,
            generation: generation,
            runtimeResolution: runtimeResolution,
            inspectedAt: Date()
        )
    }
}

#if canImport(RelaxinEngine) && canImport(RelaxinPostJailbreak) && canImport(UIKit)
import RelaxinEngine
import RelaxinPostJailbreak
import UIKit

struct ProductionEnvironmentEvidenceProvider: EnvironmentEvidenceProviding {
    private static let conservativeMinimumFreeBytes: UInt64 = 512 * 1024 * 1024

    let runtime: RelaxinRuntime
    let postJailbreakController: RLXPostJailbreakController

    func targetEvidence() async -> TargetEvidence {
        do {
            _ = try JailbreakTarget.current.confirmedManifest()
            return TargetEvidence(supported: true, reason: nil)
        } catch let error as JailbreakTarget.ConfirmationError {
            return TargetEvidence(
                supported: false,
                reason: error.localizedDescription(in: runtime.resourceBundle)
            )
        } catch {
            return TargetEvidence(supported: false, reason: error.localizedDescription)
        }
    }

    func runtimeEvidence() async -> RuntimeEvidence {
        let evidence = postJailbreakController.runtimeEvidence()
        let rootHideReportedJailbroken = evidence.rootHideReportedJailbroken.boolValue
        let processRuntimeActive = evidence.processRuntimeActive.boolValue
        let processIsPlatform = evidence.processIsPlatform.boolValue
        let active = rootHideReportedJailbroken
            && processRuntimeActive
            && processIsPlatform
        return RuntimeEvidence(
            active: active,
            rootHideReportedJailbroken: rootHideReportedJailbroken,
            processRuntimeActive: processRuntimeActive,
            processIsPlatform: processIsPlatform
        )
    }

    func bootstrapEvidence() async -> BootstrapEvidence {
        guard let evidence = try? RLXBootstrapEnvironmentInspector.inspectSystemContainerRoots() else {
            return .incomplete(reason: "Bootstrap roots could not be inspected")
        }
        if evidence.candidateCount == 0 {
            return .absent
        }
        if evidence.candidateCount > 1 {
            return .ambiguous(count: Int(evidence.candidateCount))
        }
        guard evidence.hasInstalledRelaxinMarker,
              let installedRootPath = evidence.installedRootPath
        else {
            return .incomplete(reason: evidence.findings.joined(separator: "; "))
        }
        return .validRelaxin(identity: installedRootPath)
    }

    func storageEvidence() async -> StorageEvidence {
        let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: runtime.dataDirectory.path
        )
        let freeBytes = (attributes?[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        return StorageEvidence(
            freeBytes: freeBytes,
            minimumRequiredBytes: Self.conservativeMinimumFreeBytes
        )
    }

    func packageManagerEvidence() async -> PackageManagerEvidence {
        guard let bootstrap = try? RLXBootstrapEnvironmentInspector.inspectSystemContainerRoots(),
              let installedRootPath = bootstrap.installedRootPath
        else {
            return PackageManagerEvidence(sileo: .notInstalled, zebra: .notInstalled)
        }

        let health = RLXPackageManagerHealthInspector.inspect(jailbreakRoot: installedRootPath)
        return PackageManagerEvidence(
            sileo: componentHealth(
                manager: "sileo",
                installed: health.sileoInstalled,
                healthy: health.sileoHealthy,
                findings: health.findings
            ),
            zebra: componentHealth(
                manager: "zebra",
                installed: health.zebraInstalled,
                healthy: health.zebraHealthy,
                findings: health.findings
            )
        )
    }

    func conflictEvidence() async -> [EnvironmentIssue] {
        guard let bootstrap = try? RLXBootstrapEnvironmentInspector.inspectSystemContainerRoots() else {
            return []
        }
        return bootstrap.findings.compactMap { finding in
            guard finding.hasPrefix("conflicting_marker:") else { return nil }
            return EnvironmentIssue(
                code: "conflicting-environment",
                message: finding
            )
        }
    }

    func fingerprintEvidence() async -> EnvironmentFingerprint {
        EnvironmentFingerprint(
            hardwareIdentifier: JailbreakTarget.current.deviceIdentifier,
            osVersion: JailbreakTarget.current.osVersion,
            osBuild: JailbreakTarget.current.osBuild ?? "unavailable"
        )
    }

    func generationEvidence() async -> EnvironmentGeneration {
        .current(relaxinBuild: AppInfo.build(in: runtime.resourceBundle))
    }

    func runtimeEnvironmentEvidence(
        runtime runtimeEvidence: RuntimeEvidence,
        bootstrap bootstrapEvidence: BootstrapEvidence
    ) async -> RuntimeEnvironment? {
        let target = JailbreakTarget.current
        guard let cpuFamily = target.cpuFamily,
              let osBuild = target.osBuild,
              !target.deviceIdentifier.isEmpty,
              !osBuild.isEmpty
        else { return nil }
        let baseline = UpstreamBaselineRegistry.production
        let kernelProfileMetadata = KernelProfileIntegrityMetadata.load(
            resourceBundle: runtime.resourceBundle,
            deviceIdentifier: target.deviceIdentifier,
            osBuild: osBuild
        )
        let integrity = BaselineIntegrityEvaluator.evaluate(
            manifest: baseline,
            kernelProfileMetadata: kernelProfileMetadata,
            packagedResourceDigests: [:]
        )

        return RuntimeEnvironment(
            deviceIdentifier: target.deviceIdentifier,
            cpuFamily: cpuFamily,
            architecture: "arm64e",
            osVersion: target.osVersion,
            osBuild: osBuild,
            isSimulator: target.isSimulator,
            environmentSchema: EnvironmentGeneration.currentEnvironmentSchema,
            hasInstalledBootstrap: bootstrapEvidence.isValidRelaxin,
            runtimeActive: runtimeEvidence.active,
            upstreamBaselineID: baseline.id,
            availableBaselineIntegrity: integrity.availableRequirements
        )
    }

    func runtimeBackendPolicy() async -> RuntimeBackendPolicy {
        RuntimeBackendPolicyStore(defaults: runtime.defaults).load()
    }

    private func componentHealth(
        manager: String,
        installed: Bool,
        healthy: Bool,
        findings: [String]
    ) -> PackageManagerComponentHealth {
        guard installed else { return .notInstalled }
        guard !healthy else { return .healthy }

        let sourceFinding = "\(manager)_sources_missing"
        if findings.contains(sourceFinding) {
            return .degraded(reason: sourceFinding)
        }
        let registrationFinding = "\(manager)_registration_missing"
        if findings.contains(registrationFinding) {
            return .degraded(reason: registrationFinding)
        }
        return .degraded(reason: "\(manager)_health_degraded")
    }
}
#endif
