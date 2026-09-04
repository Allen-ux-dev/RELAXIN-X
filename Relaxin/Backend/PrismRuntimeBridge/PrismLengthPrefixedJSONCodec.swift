import Foundation

enum PrismWireError: Error, Equatable {
    case payloadTooLarge
    case frameTooShort
    case invalidFrameLength(expected: Int, actual: Int)
}

struct PrismLengthPrefixedJSONCodec: Sendable {
    static let build52MaximumPayloadBytes = 1_048_576

    let maximumPayloadBytes: Int

    init(maximumPayloadBytes: Int = Self.build52MaximumPayloadBytes) {
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    func encodePayload(_ payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadBytes, payload.count <= Int(UInt32.max) else {
            throw PrismWireError.payloadTooLarge
        }

        let length = UInt32(payload.count).bigEndian
        var framed = Data()
        withUnsafeBytes(of: length) { framed.append(contentsOf: $0) }
        framed.append(payload)
        return framed
    }

    func decodeFrame(_ frame: Data) throws -> Data {
        guard frame.count >= 4 else { throw PrismWireError.frameTooShort }

        let length = frame.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        let payloadLength = Int(length)
        guard payloadLength <= maximumPayloadBytes else { throw PrismWireError.payloadTooLarge }

        let actualPayloadLength = frame.count - 4
        guard actualPayloadLength == payloadLength else {
            throw PrismWireError.invalidFrameLength(expected: payloadLength, actual: actualPayloadLength)
        }
        return frame.dropFirst(4)
    }
}
