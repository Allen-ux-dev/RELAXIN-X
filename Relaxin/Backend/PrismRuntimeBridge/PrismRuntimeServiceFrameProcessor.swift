import Foundation

struct PrismRuntimeServiceFrameProcessor: Sendable {
    let host: PrismBuild52RuntimeServiceHost
    let codec: PrismLengthPrefixedJSONCodec

    init(
        host: PrismBuild52RuntimeServiceHost,
        codec: PrismLengthPrefixedJSONCodec = PrismLengthPrefixedJSONCodec()
    ) {
        self.host = host
        self.codec = codec
    }

    func handleFrame(_ requestFrame: Data) throws -> Data {
        let requestPayload = try codec.decodeFrame(requestFrame)
        let responsePayload = try host.handleJSON(requestPayload)
        return try codec.encodePayload(responsePayload)
    }
}
