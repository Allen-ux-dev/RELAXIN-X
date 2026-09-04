import Foundation

extension String {
    init(localized key: String, bundle: Bundle) {
        self = key
    }
}


enum RuntimeSupportLevel: String {
    case supported
    case unsupported
}

struct RuntimeResolution {
    let profileID: String?
    let backendID: String?
    let backendGeneration: Int?
    let supportLevel: RuntimeSupportLevel
    let resolutionGeneration: Int
}

struct HardwareExecutionClass: RawRepresentable {
    let rawValue: String
    let soc: String

    init?(rawValue: String) {
        self.rawValue = rawValue
        self.soc = rawValue
    }

    init?(cpuFamily: UInt32) {
        self.rawValue = "test-hardware"
        self.soc = "TestSoC"
    }
}

enum DeviceInfo {
    static let modelIdentifier = "TestDevice1,1"
    static let cpuFamily: UInt32? = 0x12345678
    static let osVersion = "17.0"
    static let osBuild: String? = "21A000"
}
