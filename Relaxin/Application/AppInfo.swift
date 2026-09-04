import Foundation
import MachO

enum AppInfo {
    static func version(in resourceBundle: Bundle) -> String {
        resourceBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
    }

    static func build(in resourceBundle: Bundle) -> String {
        resourceBundle.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "0"
    }

    static func displayVersion(in resourceBundle: Bundle) -> String {
        "v\(version(in: resourceBundle))(\(build(in: resourceBundle)))"
    }

    static let arch: String = {
        guard let header = _dyld_get_image_header(0) else { return "unknown" }
        let subtype = header.pointee.cpusubtype & ~Int32(bitPattern: CPU_SUBTYPE_MASK)
        switch (header.pointee.cputype, subtype) {
        case (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E): return "arm64e"
        case (CPU_TYPE_ARM64, _): return "arm64"
        case (CPU_TYPE_X86_64, _): return "x86_64"
        default: return "unknown"
        }
    }()
}
