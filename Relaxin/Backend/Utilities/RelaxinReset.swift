import Foundation

enum RelaxinReset {
    static func perform(runtime: RelaxinRuntime) throws {
        let fileManager = FileManager.default
        var firstError: Error?

        let directories = [
            runtime.cacheDirectory,
            runtime.temporaryDirectory,
        ]

        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            do {
                for item in try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                ) {
                    do {
                        try fileManager.removeItem(at: item)
                    } catch {
                        firstError = firstError ?? error
                    }
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        URLCache.shared.removeAllCachedResponses()
        let defaults = runtime.defaults
        if let persistentDomainIdentifier = runtime.persistentDomainIdentifier {
            defaults.removePersistentDomain(forName: persistentDomainIdentifier)
        } else {
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }

        if let firstError {
            throw firstError
        }
    }
}
