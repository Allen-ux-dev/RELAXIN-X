import Foundation

private func requireDefaults(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct PrismBuild52DefaultsTests {
    static func main() throws {
        let host = PrismBuild52RuntimeDefaults.makeHandshakeOnlyHost(serviceVersion: "0.1.0")
        requireDefaults(host.runtimeIdentity == "dev.relaxin.runtime", "runtime identity must match Prism Build 52")
        requireDefaults(host.metadata["serviceID"] == "dev.relaxin.service.runtime", "service ID must match Prism Build 52")
        requireDefaults(host.supportedProtocolVersions == Set([1]), "Build 52 compatibility baseline should expose protocol v1")
        requireDefaults(host.providerKind == .native, "RELAXIN-X runtime provider should be native")
        requireDefaults(host.capabilityStates.isEmpty, "handshake-only host must not claim unwired execution capabilities")
        requireDefaults(host.backgroundSessionState == .unavailable, "unwired background service must be unavailable")
        print("PASS: Prism Build 52 runtime defaults")
    }
}
