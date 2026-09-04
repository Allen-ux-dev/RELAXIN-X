import Foundation

struct PrismCapabilityIdentifier: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum PrismCapabilityAvailability: String, Codable, Sendable {
    case available
    case degraded
    case unavailable
    case unknown
}

struct PrismCapabilityState: Codable, Hashable, Sendable {
    let identifier: PrismCapabilityIdentifier
    let availability: PrismCapabilityAvailability
    let version: Int?
    let metadata: [String: String]
}

enum PrismRuntimeServiceProviderKind: String, Codable, Sendable {
    case native
    case compatibility
    case readOnly
    case simulation
}

enum PrismRuntimeBackgroundSessionState: String, Codable, Sendable {
    case active
    case disabled
    case starting
    case unavailable
    case unknown
}

enum PrismProviderHealth: Hashable, Sendable {
    case healthy
    case degraded(reason: String)
    case unavailable(reason: String)
    case unknown(reason: String?)
}

extension PrismProviderHealth: Codable {
    private enum CodingKeys: String, CodingKey {
        case healthy
        case degraded
        case unavailable
        case unknown
    }

    private enum ReasonCodingKeys: String, CodingKey {
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.healthy) {
            _ = try? container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .healthy)
            self = .healthy
            return
        }
        if container.contains(.degraded) {
            let nested = try container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .degraded)
            self = .degraded(reason: try nested.decode(String.self, forKey: .reason))
            return
        }
        if container.contains(.unavailable) {
            let nested = try container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .unavailable)
            self = .unavailable(reason: try nested.decode(String.self, forKey: .reason))
            return
        }
        if container.contains(.unknown) {
            let nested = try container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .unknown)
            self = .unknown(reason: try nested.decodeIfPresent(String.self, forKey: .reason))
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unknown ProviderHealth case")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .healthy:
            _ = container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .healthy)
        case let .degraded(reason):
            var nested = container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .degraded)
            try nested.encode(reason, forKey: .reason)
        case let .unavailable(reason):
            var nested = container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .unavailable)
            try nested.encode(reason, forKey: .reason)
        case let .unknown(reason):
            var nested = container.nestedContainer(keyedBy: ReasonCodingKeys.self, forKey: .unknown)
            try nested.encodeIfPresent(reason, forKey: .reason)
        }
    }
}

struct PrismRuntimeServiceHelloRequest: Codable, Hashable, Sendable {
    let clientIdentifier: String
    let supportedProtocolVersions: [Int]
}

struct PrismRuntimeServiceHello: Codable, Sendable {
    let runtimeIdentity: String
    let displayName: String
    let serviceVersion: String
    let selectedProtocolVersion: Int
    let providerKind: PrismRuntimeServiceProviderKind
    let priority: Int
    let capabilityStates: [PrismCapabilityIdentifier: PrismCapabilityState]
    let health: PrismProviderHealth
    let backgroundSessionState: PrismRuntimeBackgroundSessionState
    let metadata: [String: String]
}

enum PrismRuntimeServiceRequest: Sendable {
    case handshake(PrismRuntimeServiceHelloRequest)
    case unsupported(name: String)
}

extension PrismRuntimeServiceRequest: Decodable {
    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private struct HandshakeBox: Decodable {
        let value: PrismRuntimeServiceHelloRequest

        private enum CodingKeys: String, CodingKey { case payload = "_0" }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(PrismRuntimeServiceHelloRequest.self, forKey: .payload)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Runtime service request is empty")
            )
        }
        guard container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Runtime service request must contain exactly one case")
            )
        }

        if key.stringValue == "handshake" {
            let box = try container.decode(HandshakeBox.self, forKey: key)
            self = .handshake(box.value)
        } else {
            self = .unsupported(name: key.stringValue)
        }
    }
}

enum PrismRuntimeServiceResponse: Sendable {
    case hello(PrismRuntimeServiceHello)
    case rejected(reason: String)
}

extension PrismRuntimeServiceResponse: Encodable {
    private enum CodingKeys: String, CodingKey {
        case hello
        case rejected
    }

    private enum HelloCodingKeys: String, CodingKey {
        case payload = "_0"
    }

    private enum RejectedCodingKeys: String, CodingKey {
        case reason
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(hello):
            var nested = container.nestedContainer(keyedBy: HelloCodingKeys.self, forKey: .hello)
            try nested.encode(hello, forKey: .payload)
        case let .rejected(reason):
            var nested = container.nestedContainer(keyedBy: RejectedCodingKeys.self, forKey: .rejected)
            try nested.encode(reason, forKey: .reason)
        }
    }
}
