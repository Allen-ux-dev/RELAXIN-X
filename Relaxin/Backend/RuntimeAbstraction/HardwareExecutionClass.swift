import Foundation

enum HardwareExecutionClass: String, CaseIterable, Codable, Hashable, Sendable {
    case pplDMAA12 = "ppl-dma-a12"
    case pplGFXA13 = "ppl-gfx-a13"
    case pplGFXA14M1 = "ppl-gfx-a14-m1"
    case gfxA15M2 = "gfx-a15-m2"
    case gfxA16 = "gfx-a16"
    case sptmGFXA17 = "sptm-gfx-a17"

    init?(cpuFamily: UInt32) {
        switch cpuFamily {
        case 0x07D3_4B9F: self = .pplDMAA12
        case 0x4625_04D2: self = .pplGFXA13
        case 0x1B58_8BB3: self = .pplGFXA14M1
        case 0xDA33_D83D: self = .gfxA15M2
        case 0x8765_EDEA: self = .gfxA16
        case 0x2876_F5B5: self = .sptmGFXA17
        default: return nil
        }
    }

    var soc: String {
        switch self {
        case .pplDMAA12: "A12"
        case .pplGFXA13: "A13"
        case .pplGFXA14M1: "A14/M1"
        case .gfxA15M2: "A15/M2"
        case .gfxA16: "A16"
        case .sptmGFXA17: "A17"
        }
    }
}
