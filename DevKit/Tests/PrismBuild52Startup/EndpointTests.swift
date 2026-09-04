import Foundation

@main
struct PrismBuild52EndpointTests {
    static func main() {
        precondition(
            PrismBuild52RuntimeEndpoint.socketPath(environment: [:])
                == "/var/run/relaxinx-runtime.sock"
        )
        precondition(
            PrismBuild52RuntimeEndpoint.socketPath(environment: [
                "RELAXINX_PRISM_RUNTIME_SOCKET": " /tmp/relaxinx.sock "
            ]) == "/tmp/relaxinx.sock"
        )
        precondition(
            PrismBuild52RuntimeEndpoint.socketPath(environment: [
                "RELAXINX_PRISM_RUNTIME_SOCKET": "   "
            ]) == "/var/run/relaxinx-runtime.sock"
        )
        print("PASS: Prism Build 52 endpoint resolution")
    }
}
