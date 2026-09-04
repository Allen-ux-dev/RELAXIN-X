import Darwin
import Foundation
import UIKit

enum DeviceInfo {
    private static let timebaseInfo: mach_timebase_info_data_t? = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return nil
        }
        return info
    }()

    static let osVersion: String =
        sysctlString(named: "kern.osproductversion") ?? UIDevice.current.systemVersion

    static let osBuild: String? = sysctlString(named: "kern.osversion")

    static let cpuFamily: UInt32? = {
        var value: UInt32 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname("hw.cpufamily", &value, &size, nil, 0) == 0,
              size == MemoryLayout.size(ofValue: value)
        else {
            return nil
        }
        return value
    }()

    static let os: String = "\(UIDevice.current.systemName) \(osVersion)"

    static let modelIdentifier: String = {
        // Simulator's uname reports the Mac's arch; the env carries the model.
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModel
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return string(from: systemInfo.machine)
    }()

    static let host = modelIdentifier

    static let kernel: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        return "\(string(from: systemInfo.sysname)) \(string(from: systemInfo.release))"
    }()

    static var uptime: String {
        var seconds = Int(elapsedTimeSinceBoot)
        let days = seconds / 86400
        seconds %= 86400
        let hours = seconds / 3600
        seconds %= 3600
        let minutes = seconds / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static var elapsedTimeSinceBoot: TimeInterval {
        guard let timebaseInfo else {
            return ProcessInfo.processInfo.systemUptime
        }
        // systemUptime pauses while the device sleeps; the continuous clock
        // measures the wall time users expect to have elapsed since boot.
        let nanoseconds = Double(mach_continuous_time())
            * Double(timebaseInfo.numer)
            / Double(timebaseInfo.denom)
        return nanoseconds / 1_000_000_000
    }

    private static func sysctlString(named name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size)
        let status = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname(name, buffer.baseAddress, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    private static func string(from tuple: some Any) -> String {
        withUnsafeBytes(of: tuple) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
