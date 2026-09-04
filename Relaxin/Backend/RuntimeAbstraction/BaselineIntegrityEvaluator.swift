import Foundation

struct BaselineIntegrityFailure: Equatable, Hashable, Sendable {
    let requirement: BaselineIntegrityRequirement
    let detail: String
}

struct BaselineIntegrityEvidence: Equatable, Sendable {
    let availableRequirements: Set<BaselineIntegrityRequirement>
    let failures: [BaselineIntegrityFailure]
}

enum BaselineIntegrityEvaluator {
    static func evaluate(
        manifest: UpstreamBaselineManifest,
        kernelProfileMetadata: KernelProfileIntegrityMetadata?,
        packagedResourceDigests: [String: String]
    ) -> BaselineIntegrityEvidence {
        var available: Set<BaselineIntegrityRequirement> = []
        var failures: [BaselineIntegrityFailure] = []

        if let metadata = kernelProfileMetadata {
            available.insert(.kernelProfilePresent)
            evaluateDigest(
                metadata.kernelcacheSHA256,
                requirement: .kernelcacheDigestPresent,
                available: &available,
                failures: &failures,
                missingIsFailure: true
            )

            let hasEitherSPTMDigest = metadata.sptmSHA256 != nil || metadata.txmSHA256 != nil
            evaluateDigest(
                metadata.sptmSHA256,
                requirement: .sptmDigestPresent,
                available: &available,
                failures: &failures,
                missingIsFailure: hasEitherSPTMDigest
            )
            evaluateDigest(
                metadata.txmSHA256,
                requirement: .txmDigestPresent,
                available: &available,
                failures: &failures,
                missingIsFailure: hasEitherSPTMDigest
            )
        }

        if let actual = packagedResourceDigests["bootstrap_1900.tar.zst"] {
            if normalizedDigest(actual) == normalizedDigest(manifest.bootstrapSHA256) {
                available.insert(.bootstrapDigestMatch)
            } else {
                failures.append(.init(
                    requirement: .bootstrapDigestMatch,
                    detail: "bootstrap resource digest mismatch"
                ))
            }
        }

        if let actual = packagedResourceDigests["basebin.tar"] {
            if normalizedDigest(actual) == normalizedDigest(manifest.baseBinSHA256) {
                available.insert(.baseBinDigestMatch)
            } else {
                failures.append(.init(
                    requirement: .baseBinDigestMatch,
                    detail: "BaseBin resource digest mismatch"
                ))
            }
        }

        return BaselineIntegrityEvidence(
            availableRequirements: available,
            failures: failures
        )
    }

    private static func evaluateDigest(
        _ value: String?,
        requirement: BaselineIntegrityRequirement,
        available: inout Set<BaselineIntegrityRequirement>,
        failures: inout [BaselineIntegrityFailure],
        missingIsFailure: Bool
    ) {
        guard let value else {
            if missingIsFailure {
                failures.append(.init(requirement: requirement, detail: "digest missing"))
            }
            return
        }
        guard isLowercaseSHA256(value) else {
            failures.append(.init(requirement: requirement, detail: "invalid SHA-256 metadata"))
            return
        }
        available.insert(requirement)
    }

    private static func normalizedDigest(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102:
                return true
            default:
                return false
            }
        }
    }
}
