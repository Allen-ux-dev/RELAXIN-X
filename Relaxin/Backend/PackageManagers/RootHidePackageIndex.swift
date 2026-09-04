import Foundation

struct RootHidePackageMetadata: Equatable {
    let package: String
    let version: String
    let architecture: String
    let filename: String
    let size: Int
    let sha256: String
}

enum RootHidePackageIndexError: Error, Equatable {
    case packageUnavailable
    case invalidMetadata(String)
}

enum RootHidePackageIndex {
    static let zebraPackageIdentifier = "xyz.willy.zebra"
    static let rootHideArchitecture = "iphoneos-arm64e"

    static func zebraPackage(in contents: String) throws -> RootHidePackageMetadata {
        let candidates = try stanzas(in: contents).compactMap { stanza -> RootHidePackageMetadata? in
            guard stanza["Package"] == zebraPackageIdentifier,
                  stanza["Architecture"] == rootHideArchitecture
            else {
                return nil
            }
            return try validatedMetadata(from: stanza)
        }

        guard let newest = candidates.max(by: {
            compareVersions($0.version, $1.version) == .orderedAscending
        }) else {
            throw RootHidePackageIndexError.packageUnavailable
        }
        return newest
    }

    private static func stanzas(in contents: String) throws -> [[String: String]] {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized
            .components(separatedBy: "\n\n")
            .compactMap { block in
                let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
                guard !lines.isEmpty else { return nil }
                var fields: [String: String] = [:]
                for line in lines {
                    guard let separator = line.firstIndex(of: ":") else { continue }
                    let key = String(line[..<separator])
                    let value = String(line[line.index(after: separator)...])
                        .trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
                return fields
            }
    }

    private static func validatedMetadata(
        from stanza: [String: String]
    ) throws -> RootHidePackageMetadata {
        func required(_ key: String) throws -> String {
            guard let value = stanza[key], !value.isEmpty else {
                throw RootHidePackageIndexError.invalidMetadata(key)
            }
            return value
        }

        let package = try required("Package")
        let version = try required("Version")
        let architecture = try required("Architecture")
        let filename = try required("Filename")
        let sizeText = try required("Size")
        let sha256 = try required("SHA256").lowercased()

        guard filename.hasPrefix("./debfiles/"),
              !filename.contains(".."),
              !filename.contains("\\")
        else {
            throw RootHidePackageIndexError.invalidMetadata("Filename")
        }
        guard let size = Int(sizeText), size > 0, size <= 64 * 1024 * 1024 else {
            throw RootHidePackageIndexError.invalidMetadata("Size")
        }
        guard sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit })
        else {
            throw RootHidePackageIndexError.invalidMetadata("SHA256")
        }

        return RootHidePackageMetadata(
            package: package,
            version: version,
            architecture: architecture,
            filename: filename,
            size: size,
            sha256: sha256
        )
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionTokens(lhs)
        let right = versionTokens(rhs)
        let count = max(left.count, right.count)

        for index in 0 ..< count {
            guard index < left.count else { return .orderedAscending }
            guard index < right.count else { return .orderedDescending }
            let l = left[index]
            let r = right[index]
            if l == r { continue }

            switch (l, r) {
            case let (.number(a), .number(b)):
                let aTrimmed = a.drop(while: { $0 == "0" })
                let bTrimmed = b.drop(while: { $0 == "0" })
                if aTrimmed.count != bTrimmed.count {
                    return aTrimmed.count < bTrimmed.count ? .orderedAscending : .orderedDescending
                }
                return String(aTrimmed) < String(bTrimmed) ? .orderedAscending : .orderedDescending
            case (.number, .text):
                return .orderedDescending
            case (.text, .number):
                return .orderedAscending
            case let (.text(a), .text(b)):
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private enum VersionToken: Equatable {
        case number(String)
        case text(String)
    }

    private static func versionTokens(_ version: String) -> [VersionToken] {
        var tokens: [VersionToken] = []
        var buffer = ""
        var numeric: Bool?

        func flush() {
            guard !buffer.isEmpty, let numeric else { return }
            tokens.append(numeric ? .number(buffer) : .text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        for character in version {
            let isNumeric = character.isNumber
            if let numeric, numeric != isNumeric {
                flush()
            }
            numeric = isNumeric
            buffer.append(character)
        }
        flush()
        return tokens
    }
}
