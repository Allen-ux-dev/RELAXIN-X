import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

struct ZebraPackagePreflight {
    static let repositoryBaseURL = URL(string: "https://roothide.github.io/")!
    static let packagesURL = repositoryBaseURL.appendingPathComponent("Packages")

    private let cacheDirectory: URL
    private let session: URLSession

    init(cacheDirectory: URL, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.session = session
    }

    func prepare() async throws -> URL {
        let (indexData, indexResponse) = try await session.data(from: Self.packagesURL)
        try validateHTTPResponse(indexResponse, for: Self.packagesURL)
        guard indexData.count <= 32 * 1024 * 1024,
              let index = String(data: indexData, encoding: .utf8)
        else {
            throw ZebraPackagePreflightError.invalidRepositoryIndex
        }

        let package = try RootHidePackageIndex.zebraPackage(in: index)
        let packageURL = try downloadURL(for: package)

        let directory = cacheDirectory
            .appendingPathComponent("PackageManagers", isDirectory: true)
            .appendingPathComponent("Zebra", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(
            "zebra-\(package.sha256.prefix(16)).deb"
        )
        if try cachedPackageIsValid(at: destination, metadata: package) {
            return destination
        }

        let (packageData, packageResponse) = try await session.data(from: packageURL)
        try validateHTTPResponse(packageResponse, for: packageURL)
        guard packageData.count == package.size else {
            throw ZebraPackagePreflightError.sizeMismatch(
                expected: package.size,
                actual: packageData.count
            )
        }

        let actualSHA256 = sha256Hex(packageData)
        guard actualSHA256 == package.sha256 else {
            throw ZebraPackagePreflightError.hashMismatch
        }

        let temporary = directory.appendingPathComponent(
            ".zebra-\(UUID().uuidString).tmp"
        )
        try packageData.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: temporary.path
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        pruneOldPackages(in: directory, keeping: destination)
        return destination
    }

    private func downloadURL(for package: RootHidePackageMetadata) throws -> URL {
        let relative = package.filename.dropFirst(2)
        guard let url = URL(string: String(relative), relativeTo: Self.repositoryBaseURL)?.absoluteURL,
              url.scheme == "https",
              url.host == Self.repositoryBaseURL.host
        else {
            throw ZebraPackagePreflightError.invalidPackageURL
        }
        return url
    }

    private func cachedPackageIsValid(
        at url: URL,
        metadata: RootHidePackageMetadata
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count == metadata.size,
              sha256Hex(data) == metadata.sha256
        else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    private func validateHTTPResponse(_ response: URLResponse, for url: URL) throws {
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode)
        else {
            throw ZebraPackagePreflightError.httpFailure(url)
        }
    }

    private func pruneOldPackages(in directory: URL, keeping current: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents where url.pathExtension == "deb" && url != current {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #else
        fatalError("SHA-256 verification requires CryptoKit on the target platform")
        #endif
    }
}

enum ZebraPackagePreflightError: LocalizedError {
    case invalidRepositoryIndex
    case invalidPackageURL
    case httpFailure(URL)
    case sizeMismatch(expected: Int, actual: Int)
    case hashMismatch

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryIndex:
            "The RootHide package index is invalid."
        case .invalidPackageURL:
            "The RootHide Zebra package URL is invalid."
        case let .httpFailure(url):
            "Could not download \(url.lastPathComponent)."
        case let .sizeMismatch(expected, actual):
            "The Zebra package size did not match the repository metadata (expected \(expected), got \(actual))."
        case .hashMismatch:
            "The Zebra package SHA-256 did not match the RootHide repository metadata."
        }
    }
}
