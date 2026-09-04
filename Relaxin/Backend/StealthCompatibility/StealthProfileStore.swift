import Foundation

struct StealthProfileStore: Sendable {
    let fileURL: URL

    func load() throws -> [AppStealthProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([AppStealthProfile].self, from: data)
    }

    func save(_ profiles: [AppStealthProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }

    static func invalidatingVerification(
        in profiles: [AppStealthProfile],
        for generation: EnvironmentGeneration
    ) -> [AppStealthProfile] {
        profiles.map { profile in
            guard profile.lastVerifiedGeneration != generation else { return profile }
            var invalidated = profile
            invalidated.lastVerifiedGeneration = nil
            invalidated.lastVerifiedAt = nil
            return invalidated
        }
    }
}
