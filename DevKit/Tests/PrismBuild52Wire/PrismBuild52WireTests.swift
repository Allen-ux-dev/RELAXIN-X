import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func object(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "test", code: 1)
    }
    return value
}

@main
struct PrismBuild52WireTests {
    static func main() throws {
        let codec = PrismLengthPrefixedJSONCodec()
        let payload = Data("{\"ping\":true}".utf8)
        let framed = try codec.encodePayload(payload)
        require(framed.count == payload.count + 4, "frame must add a four-byte prefix")
        require(Array(framed.prefix(4)) == [0, 0, 0, UInt8(payload.count)], "prefix must be big-endian UInt32")
        let decodedPayload = try codec.decodeFrame(framed)
        require(decodedPayload == payload, "codec must round-trip payload")

        let tooLarge = Data(repeating: 0x41, count: 1_048_577)
        do {
            _ = try codec.encodePayload(tooLarge)
            require(false, "payload above 1 MiB must be rejected")
        } catch PrismWireError.payloadTooLarge {
            // expected
        }

        let installCapability = PrismCapabilityState(
            identifier: PrismCapabilityIdentifier(rawValue: "dev.prism.capability.app-install"),
            availability: .unavailable,
            version: nil,
            metadata: ["reason": "provider-not-wired"]
        )

        let host = PrismBuild52RuntimeServiceHost(
            runtimeIdentity: "dev.relaxinx.runtime",
            displayName: "RELAXIN-X Runtime",
            serviceVersion: "0.1.0",
            supportedProtocolVersions: [1],
            providerKind: .native,
            priority: 100,
            capabilityStates: [installCapability],
            health: .degraded(reason: "application backend not wired"),
            backgroundSessionState: .unavailable,
            metadata: ["bridge": "prism-build52"]
        )

        let handshakeJSON = Data(#"{"handshake":{"_0":{"clientIdentifier":"dev.allenux.prism","supportedProtocolVersions":[1,2]}}}"#.utf8)
        let handshakeResponse = try host.handleJSON(handshakeJSON)
        let handshakeObject = try object(handshakeResponse)
        guard
            let helloBox = handshakeObject["hello"] as? [String: Any],
            let hello = helloBox["_0"] as? [String: Any]
        else {
            require(false, "handshake must return Prism RuntimeServiceResponse.hello synthesized shape")
            return
        }
        require(hello["runtimeIdentity"] as? String == "dev.relaxinx.runtime", "runtime identity must be stable")
        require(hello["selectedProtocolVersion"] as? Int == 1, "must negotiate highest common protocol version")
        require(hello["providerKind"] as? String == "native", "provider must be native")
        require(hello["backgroundSessionState"] as? String == "unavailable", "background must fail closed")
        require(String(data: handshakeResponse, encoding: .utf8)?.contains("/var/") == false, "hello must not expose privileged paths")

        let incompatibleJSON = Data(#"{"handshake":{"_0":{"clientIdentifier":"dev.allenux.prism","supportedProtocolVersions":[7,8]}}}"#.utf8)
        let incompatibleResponse = try host.handleJSON(incompatibleJSON)
        let incompatibleObject = try object(incompatibleResponse)
        guard let rejected = incompatibleObject["rejected"] as? [String: Any] else {
            require(false, "incompatible protocol must return rejected")
            return
        }
        require((rejected["reason"] as? String)?.contains("protocolIncompatible") == true, "rejection must identify protocol mismatch")

        let installJSON = Data(#"{"install":{"artifact":{"stagingIdentifier":"opaque-123","sha256":null}}}"#.utf8)
        let installResponse = try host.handleJSON(installJSON)
        let installObject = try object(installResponse)
        guard let installRejected = installObject["rejected"] as? [String: Any] else {
            require(false, "unwired install backend must reject instead of reporting success")
            return
        }
        require((installRejected["reason"] as? String)?.contains("providerUnavailable") == true, "unwired operation must fail closed")

        print("PASS: Prism Build 52 wire compatibility")
    }
}
