import Foundation

struct KernelProfileIntegrityMetadata: Equatable, Hashable, Sendable {
    let kernelcacheSHA256: String?
    let sptmSHA256: String?
    let txmSHA256: String?

    static func load(
        resourceBundle: Bundle,
        deviceIdentifier: String,
        osBuild: String
    ) -> KernelProfileIntegrityMetadata? {
        guard !deviceIdentifier.isEmpty, !osBuild.isEmpty,
              let url = resourceBundle.url(forResource: "KernelOffsets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let table = root as? [String: Any],
              let profiles = table["profiles"] as? [[String: Any]],
              let index = table["index"] as? [String: Any]
        else { return nil }

        let key = "\(deviceIdentifier)|\(osBuild)"
        let rawPosition = index[key]
        let position: Int?
        if let number = rawPosition as? NSNumber {
            position = number.intValue
        } else if let value = rawPosition as? Int {
            position = value
        } else {
            position = nil
        }
        guard let position, profiles.indices.contains(position) else { return nil }

        let profile = profiles[position]
        return KernelProfileIntegrityMetadata(
            kernelcacheSHA256: profile["kernelcacheSHA256"] as? String,
            sptmSHA256: profile["sptmSHA256"] as? String,
            txmSHA256: profile["txmSHA256"] as? String
        )
    }
}
