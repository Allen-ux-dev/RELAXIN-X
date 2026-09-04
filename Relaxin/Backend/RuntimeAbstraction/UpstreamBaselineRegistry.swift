import Foundation

enum UpstreamBaselineRegistry {
    static let production = UpstreamBaselineManifest(
        id: "relaxin.upstream.v0.5.0.20260826",
        upstreamProduct: "Relaxin",
        upstreamVersion: "0.5.0",
        releaseSHA256: "277ded7b324f619a993423eb47c76e09680da1087f14626930c941fe83edc0e9",
        kernelOffsetGeneration: "2026-08-26T07:38:29+00:00",
        kernelOffsetSHA256: "2b3791cb13d00f43761af7e9ce136d22ecd1f07db9d34fc4d31c1e71a5bc6e9c",
        bootstrapGeneration: "1900",
        bootstrapSHA256: "466d3fc0e1b99f1128ff9f307237b157b36de816853896277447709e2a774aeb",
        baseBinGeneration: "3716385fe8",
        baseBinSHA256: "a83d8139021a71c9c49656f6d5f57dd500500e9a6854f54c6c03f56b52a97eab",
        minimumOSVersion: "16.5.1",
        maximumOSVersion: "17.3.1",
        supportedBuilds: [
            "20F75", "20G75", "20G81", "20H19", "20H30", "20H115",
            "21A329", "21A331", "21A340", "21A350", "21A351", "21A360",
            "21B74", "21B80", "21B91", "21B101", "21C62", "21C66",
            "21D50", "21D61",
        ],
        hardwareSupportSet: [
            "ppl-dma-a12",
            "ppl-gfx-a13",
            "ppl-gfx-a14-m1",
            "gfx-a15-m2",
            "gfx-a16",
            "sptm-gfx-a17",
        ],
        requiredCapabilities: [
            "verifyRuntime",
            "verifyBootstrap",
            "baselineIntegrityValidation",
            "hardwareRegistryV2",
        ],
        resourceDigests: [
            "KernelOffsets.plist": "2b3791cb13d00f43761af7e9ce136d22ecd1f07db9d34fc4d31c1e71a5bc6e9c",
            "basebin.tar": "a83d8139021a71c9c49656f6d5f57dd500500e9a6854f54c6c03f56b52a97eab",
            "bootstrap_1900.tar.zst": "466d3fc0e1b99f1128ff9f307237b157b36de816853896277447709e2a774aeb",
            "sileo.deb": "b23e51371938bb6257ba82abdcdae9a6519755556b874b06672868c64843a0f6",
            "roothideapp.deb": "b8f075e1844709845962900b22fe71136a66369a2c35bb1201087f2fd9476b7d",
        ],
        manifestSchema: 1
    )

    static let supportedManifestSchema = 1

    static func manifest(id: String) -> UpstreamBaselineManifest? {
        production.id == id ? production : nil
    }

    static func supports(_ manifest: UpstreamBaselineManifest) -> Bool {
        manifest.manifestSchema == supportedManifestSchema
    }
}
