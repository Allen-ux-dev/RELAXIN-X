import Foundation

enum HardwareSupportRegistry {
    static let production: [HardwareSupportDescriptor] = [
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.pplDMAA12.rawValue,
            displaySoC: HardwareExecutionClass.pplDMAA12.soc,
            cpuFamilies: [0x07D3_4B9F],
            legacyExecutionClass: .pplDMAA12,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
        ),
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.pplGFXA13.rawValue,
            displaySoC: HardwareExecutionClass.pplGFXA13.soc,
            cpuFamilies: [0x4625_04D2],
            legacyExecutionClass: .pplGFXA13,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
        ),
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.pplGFXA14M1.rawValue,
            displaySoC: HardwareExecutionClass.pplGFXA14M1.soc,
            cpuFamilies: [0x1B58_8BB3],
            legacyExecutionClass: .pplGFXA14M1,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
        ),
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.gfxA15M2.rawValue,
            displaySoC: HardwareExecutionClass.gfxA15M2.soc,
            cpuFamilies: [0xDA33_D83D],
            legacyExecutionClass: .gfxA15M2,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
        ),
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.gfxA16.rawValue,
            displaySoC: HardwareExecutionClass.gfxA16.soc,
            cpuFamilies: [0x8765_EDEA],
            legacyExecutionClass: .gfxA16,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [.kernelProfilePresent, .kernelcacheDigestPresent]
        ),
        HardwareSupportDescriptor(
            id: HardwareExecutionClass.sptmGFXA17.rawValue,
            displaySoC: HardwareExecutionClass.sptmGFXA17.soc,
            cpuFamilies: [0x2876_F5B5],
            legacyExecutionClass: .sptmGFXA17,
            status: .supported,
            minimumBackendGeneration: 2,
            requiredCapabilities: [.verifyRuntime, .verifyBootstrap],
            requiredBaselineIntegrity: [
                .kernelProfilePresent,
                .kernelcacheDigestPresent,
                .sptmDigestPresent,
                .txmDigestPresent,
            ]
        ),
    ]

    static func resolve(cpuFamily: UInt32) -> HardwareSupportDescriptor? {
        resolve(cpuFamily: cpuFamily, descriptors: production)
    }

    static func resolve(
        cpuFamily: UInt32,
        descriptors: [HardwareSupportDescriptor]
    ) -> HardwareSupportDescriptor? {
        descriptors
            .filter { $0.cpuFamilies.contains(cpuFamily) }
            .sorted { $0.id < $1.id }
            .first
    }

    static func descriptor(id: String) -> HardwareSupportDescriptor? {
        production.first { $0.id == id }
    }
}
