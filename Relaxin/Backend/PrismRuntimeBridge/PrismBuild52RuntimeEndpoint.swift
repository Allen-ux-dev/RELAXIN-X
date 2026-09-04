import Foundation

enum PrismBuild52RuntimeEndpoint {
    static let environmentKey = "RELAXINX_PRISM_RUNTIME_SOCKET"
    static let defaultSocketPath = "/var/run/relaxinx-runtime.sock"

    static func socketPath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        guard let raw = environment[environmentKey] else {
            return defaultSocketPath
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSocketPath : trimmed
    }
}
