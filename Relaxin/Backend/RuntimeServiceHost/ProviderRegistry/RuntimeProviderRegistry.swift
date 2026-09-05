import Foundation

enum RuntimeProviderResolution: Equatable, Sendable {
    case selected(RuntimeProviderDescriptor)
    case unavailable
}

struct PinnedRuntimeProvider: Equatable, Hashable, Codable, Sendable {
    let transactionID: String
    let providerID: String
    let serviceID: String
    let providerKind: ProviderKind
    let sessionGeneration: Int
}

enum RuntimeProviderPinValidation: Equatable, Sendable {
    case valid
    case missingProvider
    case staleSession
    case identityMismatch
}

struct RuntimeProviderRegistry: Sendable {
    private let providers: [RuntimeProviderDescriptor]

    init(providers: [RuntimeProviderDescriptor]) {
        self.providers = providers
    }

    func resolve(serviceID: String) -> RuntimeProviderResolution {
        let candidates = providers
            .filter { $0.serviceID == serviceID && $0.isUsable }
            .sorted { lhs, rhs in
                if lhs.providerKind.resolutionRank != rhs.providerKind.resolutionRank {
                    return lhs.providerKind.resolutionRank > rhs.providerKind.resolutionRank
                }
                if lhs.sessionGeneration != rhs.sessionGeneration {
                    return lhs.sessionGeneration > rhs.sessionGeneration
                }
                return lhs.providerID < rhs.providerID
            }
        guard let selected = candidates.first else { return .unavailable }
        return .selected(selected)
    }

    func pin(
        serviceID: String,
        transactionID: String
    ) -> Result<PinnedRuntimeProvider, RuntimeServiceError> {
        switch resolve(serviceID: serviceID) {
        case let .selected(provider):
            return .success(
                PinnedRuntimeProvider(
                    transactionID: transactionID,
                    providerID: provider.providerID,
                    serviceID: provider.serviceID,
                    providerKind: provider.providerKind,
                    sessionGeneration: provider.sessionGeneration
                )
            )
        case .unavailable:
            return .failure(.providerUnavailable)
        }
    }

    func validate(pin: PinnedRuntimeProvider) -> RuntimeProviderPinValidation {
        guard let provider = providers.first(where: { $0.providerID == pin.providerID }) else {
            return .missingProvider
        }
        guard provider.serviceID == pin.serviceID, provider.providerKind == pin.providerKind else {
            return .identityMismatch
        }
        guard provider.sessionGeneration == pin.sessionGeneration else {
            return .staleSession
        }
        return provider.isUsable ? .valid : .missingProvider
    }
}

private extension ProviderKind {
    var resolutionRank: Int {
        switch self {
        case .native: 4
        case .compatibility: 3
        case .readOnly: 2
        case .simulation: 1
        }
    }
}
