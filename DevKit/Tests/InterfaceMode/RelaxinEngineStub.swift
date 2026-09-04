import Foundation

public final class RLXRuntimeEnvironment {
    public static let `default` = RLXRuntimeEnvironment()

    public let resourceBundle = Bundle.main
    public let dataDirectoryURL = FileManager.default.temporaryDirectory
    public let cacheDirectoryURL = FileManager.default.temporaryDirectory
    public let temporaryDirectoryURL = FileManager.default.temporaryDirectory
}
