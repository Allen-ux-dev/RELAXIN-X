import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let manifest = UpstreamBaselineRegistry.production
require(manifest.id == "relaxin.upstream.v0.5.0.20260826", "production baseline id")
require(manifest.upstreamVersion == "0.5.0", "upstream version")
require(manifest.kernelOffsetSHA256 == "2b3791cb13d00f43761af7e9ce136d22ecd1f07db9d34fc4d31c1e71a5bc6e9c", "kernel offsets release digest")
require(manifest.bootstrapGeneration == "1900", "bootstrap generation")
require(manifest.manifestSchema == 1, "manifest schema")
require(manifest.resourceDigests["basebin.tar"] == "a83d8139021a71c9c49656f6d5f57dd500500e9a6854f54c6c03f56b52a97eab", "basebin digest")
require(manifest.resourceDigests["bootstrap_1900.tar.zst"] == "466d3fc0e1b99f1128ff9f307237b157b36de816853896277447709e2a774aeb", "bootstrap digest")
require(manifest.resourceDigests["sileo.deb"] == "b23e51371938bb6257ba82abdcdae9a6519755556b874b06672868c64843a0f6", "sileo digest")
require(manifest.resourceDigests["roothideapp.deb"] == "b8f075e1844709845962900b22fe71136a66369a2c35bb1201087f2fd9476b7d", "roothide digest")
require(UpstreamBaselineRegistry.manifest(id: manifest.id) == manifest, "registry lookup")
require(UpstreamBaselineRegistry.manifest(id: "missing") == nil, "unknown baseline lookup")

let encoded = try JSONEncoder().encode(manifest)
let decoded = try JSONDecoder().decode(UpstreamBaselineManifest.self, from: encoded)
require(decoded == manifest, "baseline Codable round-trip")

require(Set(BaselineIntegrityRequirement.allCases).contains(.sptmDigestPresent), "SPTM integrity requirement exists")
require(Set(BaselineIntegrityRequirement.allCases).contains(.txmDigestPresent), "TXM integrity requirement exists")

print("PASS RuntimeBaseline manifest")

let hardwarePairs: [(UInt32, HardwareExecutionClass, String)] = [
    (0x07D3_4B9F, .pplDMAA12, "ppl-dma-a12"),
    (0x4625_04D2, .pplGFXA13, "ppl-gfx-a13"),
    (0x1B58_8BB3, .pplGFXA14M1, "ppl-gfx-a14-m1"),
    (0xDA33_D83D, .gfxA15M2, "gfx-a15-m2"),
    (0x8765_EDEA, .gfxA16, "gfx-a16"),
    (0x2876_F5B5, .sptmGFXA17, "sptm-gfx-a17"),
]
for (cpuFamily, legacyClass, descriptorID) in hardwarePairs {
    let descriptor = HardwareSupportRegistry.resolve(cpuFamily: cpuFamily)
    require(descriptor?.id == descriptorID, "hardware registry id for \(descriptorID)")
    require(descriptor?.legacyExecutionClass == legacyClass, "legacy hardware parity for \(descriptorID)")
    require(descriptor?.status == .supported, "current production hardware remains supported")
    require(HardwareExecutionClass(cpuFamily: cpuFamily) == legacyClass, "legacy enum mapping unchanged")
}

let a17Descriptor = HardwareSupportRegistry.resolve(cpuFamily: 0x2876_F5B5)
require(a17Descriptor?.requiredBaselineIntegrity.contains(.sptmDigestPresent) == true, "A17 requires SPTM digest metadata")
require(a17Descriptor?.requiredBaselineIntegrity.contains(.txmDigestPresent) == true, "A17 requires TXM digest metadata")
require(a17Descriptor?.minimumBackendGeneration == 2, "A17 v0.5.0 baseline requires backend generation 2")

let future = HardwareSupportDescriptor(
    id: "future-recognized",
    displaySoC: "Future",
    cpuFamilies: [0xDEAD_BEEF],
    legacyExecutionClass: nil,
    status: .recognized,
    minimumBackendGeneration: 99,
    requiredCapabilities: [],
    requiredBaselineIntegrity: []
)
let recognized = HardwareSupportRegistry.resolve(cpuFamily: 0xDEAD_BEEF, descriptors: [future])
require(recognized?.status == .recognized, "future hardware can be recognized")
require(recognized?.legacyExecutionClass == nil, "recognized future hardware has no engine execution class")
require(HardwareSupportRegistry.resolve(cpuFamily: 0xDEAD_BEEF) == nil, "future hardware is not production-supported by accidental registry entry")

let registryEnvironment = RuntimeEnvironment(
    deviceIdentifier: "iPhone12,1",
    cpuFamily: 0x4625_04D2,
    architecture: "arm64e",
    osVersion: "17.3.1",
    osBuild: "21D61",
    isSimulator: false,
    environmentSchema: 1,
    hasInstalledBootstrap: false,
    runtimeActive: false
)
require(registryEnvironment.hardwareSupportID == "ppl-gfx-a13", "runtime environment exposes hardware support id")

print("PASS RuntimeBaseline hardware registry")

let productionProfile = RuntimeProfileRegistry.production[0]
require(productionProfile.baselineID == UpstreamBaselineRegistry.production.id, "production profile binds v0.5.0 baseline")
require(productionProfile.minimumBackendGeneration == 2, "production profile requires backend generation 2")
require(productionProfile.hardwareSupportIDs.contains("sptm-gfx-a17"), "production profile carries product hardware ids")

let productionBackend = LegacyRelaxinRuntimeBackend().descriptor
require(productionBackend.backendGeneration == 2, "current engine adapter generation bumped to 2")
require(productionBackend.capabilities.contains(.baselineIntegrityValidation), "source backend validates baseline integrity")
require(productionBackend.capabilities.contains(.hardwareRegistryV2), "source backend supports hardware registry v2")
require(!productionBackend.capabilities.contains(.userspaceRebootV2), "binary-only userspace reboot v2 not falsely advertised")
require(!productionBackend.capabilities.contains(.missingTargetPathRepair), "binary-only missing-path repair not falsely advertised")
require(RuntimeProfileResolver.resolutionGeneration == 2, "resolver generation 2")

func v2Environment(
    cpuFamily: UInt32,
    baselineID: String? = UpstreamBaselineRegistry.production.id,
    integrity: Set<BaselineIntegrityRequirement>
) -> RuntimeEnvironment {
    RuntimeEnvironment(
        deviceIdentifier: cpuFamily == 0x2876_F5B5 ? "iPhone16,1" : "iPhone12,1",
        cpuFamily: cpuFamily,
        architecture: "arm64e",
        osVersion: "17.3.1",
        osBuild: "21D61",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false,
        upstreamBaselineID: baselineID,
        availableBaselineIntegrity: integrity
    )
}

let a13Resolution = RuntimeProfileResolver.resolve(
    environment: v2Environment(
        cpuFamily: 0x4625_04D2,
        integrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    ),
    profiles: RuntimeProfileRegistry.production,
    backends: RuntimeBackendRegistry.production,
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(a13Resolution.supportLevel == .supported, "A13 resolves on v0.5.0 baseline")
require(a13Resolution.baselineID == UpstreamBaselineRegistry.production.id, "resolution records baseline identity")

let a17Integrity: Set<BaselineIntegrityRequirement> = [
    .kernelProfilePresent, .kernelcacheDigestPresent, .sptmDigestPresent, .txmDigestPresent
]
let a17Resolution = RuntimeProfileResolver.resolve(
    environment: v2Environment(cpuFamily: 0x2876_F5B5, integrity: a17Integrity),
    profiles: RuntimeProfileRegistry.production,
    backends: RuntimeBackendRegistry.production,
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(a17Resolution.supportLevel == .supported, "A17 resolves when v0.5.0 integrity metadata is present")

let a17MissingMetadata = RuntimeProfileResolver.resolve(
    environment: v2Environment(
        cpuFamily: 0x2876_F5B5,
        integrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    ),
    profiles: RuntimeProfileRegistry.production,
    backends: RuntimeBackendRegistry.production,
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(a17MissingMetadata.supportLevel == .unsupported, "A17 is rejected without SPTM/TXM metadata")
require(a17MissingMetadata.rejectedCandidates.contains { $0.reasonCode == .requiredBaselineMetadataMissing }, "A17 metadata rejection is structured")

let missingBaseline = RuntimeProfileResolver.resolve(
    environment: v2Environment(
        cpuFamily: 0x4625_04D2,
        baselineID: "missing.baseline",
        integrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    ),
    profiles: RuntimeProfileRegistry.production,
    backends: RuntimeBackendRegistry.production,
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(missingBaseline.supportLevel == .unsupported, "missing baseline rejects resolution")
require(missingBaseline.rejectedCandidates.contains { $0.reasonCode == .baselineMissing }, "missing baseline rejection code")

let oldBackend = RuntimeBackendDescriptor(
    id: "old-generation",
    displayName: "Old Generation",
    maturity: .stable,
    supportedProfileIDs: [productionProfile.id],
    capabilities: productionBackend.capabilities,
    hardwareClasses: [.pplGFXA13],
    minimumEnvironmentSchema: 1,
    backendGeneration: 1
)
let oldGenerationResolution = RuntimeProfileResolver.resolve(
    environment: v2Environment(
        cpuFamily: 0x4625_04D2,
        integrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
    ),
    profiles: [productionProfile],
    backends: [oldBackend],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil)
)
require(oldGenerationResolution.supportLevel == .unsupported, "backend below profile generation floor rejects")
require(oldGenerationResolution.rejectedCandidates.contains { $0.reasonCode == .backendGenerationTooOld }, "backend generation rejection code")

let futureDescriptor = HardwareSupportDescriptor(
    id: "future-recognized-v2",
    displaySoC: "Future",
    cpuFamilies: [0xCAFE_BABE],
    legacyExecutionClass: nil,
    status: .recognized,
    minimumBackendGeneration: 99,
    requiredCapabilities: [],
    requiredBaselineIntegrity: []
)
let futureProfile = RuntimeProfile(
    id: "future-profile",
    displayName: "Future Profile",
    osConstraint: .versionRange(minimum: "16.5.1", maximum: "17.3.1"),
    exactBuilds: [],
    hardwareClasses: [],
    requiredArchitecture: "arm64e",
    requiredBackendCapabilities: [],
    optionalCapabilities: [],
    bootstrapGeneration: "1900",
    minimumEnvironmentSchema: 1,
    recoveryPolicy: .allowed,
    maturityFloor: .stable,
    baselineID: UpstreamBaselineRegistry.production.id,
    hardwareSupportIDs: [futureDescriptor.id],
    minimumBackendGeneration: 1,
    requiredBaselineIntegrity: []
)
let futureResolution = RuntimeProfileResolver.resolve(
    environment: RuntimeEnvironment(
        deviceIdentifier: "FutureDevice",
        cpuFamily: 0xCAFE_BABE,
        architecture: "arm64e",
        osVersion: "17.3.1",
        osBuild: "21D61",
        isSimulator: false,
        environmentSchema: 1,
        hasInstalledBootstrap: false,
        runtimeActive: false,
        upstreamBaselineID: UpstreamBaselineRegistry.production.id,
        availableBaselineIntegrity: []
    ),
    profiles: [futureProfile],
    backends: [],
    policy: .init(experimentalEnabled: false, preferredBackendID: nil),
    hardwareDescriptors: [futureDescriptor]
)
require(futureResolution.supportLevel == .unsupported, "recognized future hardware is not supported")
require(futureResolution.rejectedCandidates.contains { $0.reasonCode == .hardwareRecognizedButUnsupported }, "recognized future hardware reason")

print("PASS RuntimeBaseline resolver v2")

let a13Metadata = KernelProfileIntegrityMetadata(
    kernelcacheSHA256: String(repeating: "a", count: 64),
    sptmSHA256: nil,
    txmSHA256: nil
)
let a13IntegrityEvidence = BaselineIntegrityEvaluator.evaluate(
    manifest: UpstreamBaselineRegistry.production,
    kernelProfileMetadata: a13Metadata,
    packagedResourceDigests: [:]
)
require(a13IntegrityEvidence.availableRequirements.contains(.kernelProfilePresent), "kernel profile presence recorded")
require(a13IntegrityEvidence.availableRequirements.contains(.kernelcacheDigestPresent), "kernelcache digest presence recorded")
require(!a13IntegrityEvidence.availableRequirements.contains(.sptmDigestPresent), "A13 metadata need not invent SPTM digest")
require(a13IntegrityEvidence.failures.isEmpty, "valid A13 metadata has no failures")

let a17Metadata = KernelProfileIntegrityMetadata(
    kernelcacheSHA256: String(repeating: "b", count: 64),
    sptmSHA256: String(repeating: "c", count: 64),
    txmSHA256: String(repeating: "d", count: 64)
)
let a17IntegrityEvidence = BaselineIntegrityEvaluator.evaluate(
    manifest: UpstreamBaselineRegistry.production,
    kernelProfileMetadata: a17Metadata,
    packagedResourceDigests: [
        "basebin.tar": UpstreamBaselineRegistry.production.baseBinSHA256,
        "bootstrap_1900.tar.zst": UpstreamBaselineRegistry.production.bootstrapSHA256,
    ]
)
for requirement in [
    BaselineIntegrityRequirement.kernelProfilePresent,
    .kernelcacheDigestPresent,
    .sptmDigestPresent,
    .txmDigestPresent,
    .bootstrapDigestMatch,
    .baseBinDigestMatch,
] {
    require(a17IntegrityEvidence.availableRequirements.contains(requirement), "A17 integrity has \(requirement.rawValue)")
}
require(a17IntegrityEvidence.failures.isEmpty, "valid A17 metadata and resource digests have no failures")

let malformedIntegrityEvidence = BaselineIntegrityEvaluator.evaluate(
    manifest: UpstreamBaselineRegistry.production,
    kernelProfileMetadata: .init(kernelcacheSHA256: "ABC", sptmSHA256: "xyz", txmSHA256: nil),
    packagedResourceDigests: ["bootstrap_1900.tar.zst": "wrong"]
)
require(!malformedIntegrityEvidence.availableRequirements.contains(.kernelcacheDigestPresent), "malformed kernelcache digest rejected")
require(!malformedIntegrityEvidence.availableRequirements.contains(.sptmDigestPresent), "malformed SPTM digest rejected")
require(!malformedIntegrityEvidence.availableRequirements.contains(.txmDigestPresent), "missing TXM digest rejected")
require(!malformedIntegrityEvidence.availableRequirements.contains(.bootstrapDigestMatch), "mismatched bootstrap digest rejected")
require(malformedIntegrityEvidence.failures.contains { $0.requirement == .kernelcacheDigestPresent }, "kernel digest failure recorded")
require(malformedIntegrityEvidence.failures.contains { $0.requirement == .bootstrapDigestMatch }, "bootstrap digest mismatch recorded")

print("PASS RuntimeBaseline integrity evaluator")
