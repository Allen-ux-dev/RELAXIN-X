import Foundation

enum RuntimeProfileResolver {
    static let resolutionGeneration = 2

    private struct Candidate {
        let profile: RuntimeProfile
        let backend: RuntimeBackendDescriptor
        let exactBuild: Bool
        let baseline: UpstreamBaselineManifest?
    }

    static func resolve(
        environment: RuntimeEnvironment,
        profiles: [RuntimeProfile],
        backends: [RuntimeBackendDescriptor],
        policy: RuntimeBackendPolicy,
        baselines: [UpstreamBaselineManifest] = [UpstreamBaselineRegistry.production],
        hardwareDescriptors: [HardwareSupportDescriptor] = HardwareSupportRegistry.production
    ) -> RuntimeResolution {
        let identity = environmentIdentity(environment)
        var rejected: [RuntimeRejectedCandidate] = []

        guard !environment.isSimulator else {
            return unsupported(identity: identity, rejected: [
                .init(profileID: nil, backendID: nil, reasonCode: .simulatorUnsupported, detail: "Simulator targets are not eligible")
            ])
        }
        guard !environment.deviceIdentifier.isEmpty,
              !environment.osVersion.isEmpty,
              !environment.osBuild.isEmpty,
              let cpuFamily = environment.cpuFamily
        else {
            return unsupported(identity: identity, rejected: [
                .init(profileID: nil, backendID: nil, reasonCode: .identityMissing, detail: "Required runtime identity evidence is missing")
            ])
        }

        let hardwareDescriptor = HardwareSupportRegistry.resolve(
            cpuFamily: cpuFamily,
            descriptors: hardwareDescriptors
        )

        var matchingProfiles: [(RuntimeProfile, UpstreamBaselineManifest?)] = []
        for profile in profiles.sorted(by: { $0.id < $1.id }) {
            var baseline: UpstreamBaselineManifest?
            if let baselineID = profile.baselineID {
                guard environment.upstreamBaselineID == baselineID,
                      let candidateBaseline = baselines.first(where: { $0.id == baselineID })
                else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .baselineMissing,
                        detail: environment.upstreamBaselineID ?? "none"
                    ))
                    continue
                }
                guard UpstreamBaselineRegistry.supports(candidateBaseline) else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .baselineSchemaUnsupported,
                        detail: String(candidateBaseline.manifestSchema)
                    ))
                    continue
                }
                baseline = candidateBaseline
            }

            if !profile.osConstraint.matches(environment.osVersion) {
                rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .profileOSMismatch, detail: environment.osVersion))
                continue
            }
            if !profile.exactBuilds.isEmpty && !profile.exactBuilds.contains(environment.osBuild) {
                rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .profileBuildMismatch, detail: environment.osBuild))
                continue
            }

            if !profile.hardwareSupportIDs.isEmpty {
                guard let hardwareDescriptor else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .hardwareClassMismatch,
                        detail: String(format: "0x%08x", cpuFamily)
                    ))
                    continue
                }
                guard profile.hardwareSupportIDs.contains(hardwareDescriptor.id) else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .hardwareClassMismatch,
                        detail: hardwareDescriptor.id
                    ))
                    continue
                }
                switch hardwareDescriptor.status {
                case .supported:
                    break
                case .experimental:
                    guard policy.experimentalEnabled else {
                        rejected.append(.init(
                            profileID: profile.id,
                            backendID: nil,
                            reasonCode: .hardwareExperimentalDisabled,
                            detail: hardwareDescriptor.id
                        ))
                        continue
                    }
                case .recognized, .unsupported:
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .hardwareRecognizedButUnsupported,
                        detail: hardwareDescriptor.id
                    ))
                    continue
                }
                if let baseline,
                   !baseline.hardwareSupportSet.isEmpty,
                   !baseline.hardwareSupportSet.contains(hardwareDescriptor.id)
                {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: nil,
                        reasonCode: .hardwareRecognizedButUnsupported,
                        detail: "\(hardwareDescriptor.id) is not in baseline \(baseline.id)"
                    ))
                    continue
                }
            } else {
                guard let hardware = environment.hardwareExecutionClass,
                      profile.hardwareClasses.contains(hardware)
                else {
                    rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .hardwareClassMismatch, detail: environment.hardwareExecutionClass?.rawValue ?? "unknown"))
                    continue
                }
            }

            guard environment.architecture == profile.requiredArchitecture else {
                rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .architectureMismatch, detail: environment.architecture))
                continue
            }
            guard environment.environmentSchema >= profile.minimumEnvironmentSchema else {
                rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .environmentSchemaTooOld, detail: String(environment.environmentSchema)))
                continue
            }

            let requiredIntegrity: Set<BaselineIntegrityRequirement>
            if profile.baselineID != nil {
                requiredIntegrity = profile.requiredBaselineIntegrity.union(
                    hardwareDescriptor?.requiredBaselineIntegrity ?? []
                )
            } else {
                requiredIntegrity = profile.requiredBaselineIntegrity
            }
            let missingIntegrity = requiredIntegrity.subtracting(environment.availableBaselineIntegrity)
            guard missingIntegrity.isEmpty else {
                rejected.append(.init(
                    profileID: profile.id,
                    backendID: nil,
                    reasonCode: .requiredBaselineMetadataMissing,
                    detail: missingIntegrity.map(\.rawValue).sorted().joined(separator: ",")
                ))
                continue
            }

            matchingProfiles.append((profile, baseline))
        }

        guard !matchingProfiles.isEmpty else {
            rejected.append(
                .init(
                    profileID: nil,
                    backendID: nil,
                    reasonCode: .runtimeProfileMissing,
                    detail: "No registered runtime profile matches the observed environment"
                )
            )
            return unsupported(identity: identity, rejected: rejected)
        }

        var candidates: [Candidate] = []
        for (profile, baseline) in matchingProfiles {
            let profileBackends = backends.filter { $0.supportedProfileIDs.contains(profile.id) }
            if profileBackends.isEmpty {
                rejected.append(.init(profileID: profile.id, backendID: nil, reasonCode: .runtimeBackendMissing, detail: "No registered backend advertises this profile"))
                continue
            }
            for backend in profileBackends.sorted(by: { $0.id < $1.id }) {
                if backend.maturity == .legacy && profile.maturityFloor != .legacy {
                    rejected.append(
                        .init(
                            profileID: profile.id,
                            backendID: backend.id,
                            reasonCode: .backendMaturityIncompatible,
                            detail: "Legacy backend is not permitted by this runtime profile"
                        )
                    )
                    continue
                }
                if backend.maturity == .experimental && !policy.experimentalEnabled {
                    rejected.append(.init(profileID: profile.id, backendID: backend.id, reasonCode: .experimentalBackendDisabled, detail: "Experimental backend requires explicit opt-in"))
                    continue
                }
                guard environment.environmentSchema >= backend.minimumEnvironmentSchema else {
                    rejected.append(.init(profileID: profile.id, backendID: backend.id, reasonCode: .environmentSchemaTooOld, detail: String(environment.environmentSchema)))
                    continue
                }

                let generationFloor = max(
                    profile.minimumBackendGeneration,
                    profile.baselineID == nil ? 1 : (hardwareDescriptor?.minimumBackendGeneration ?? 1)
                )
                guard backend.backendGeneration >= generationFloor else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: backend.id,
                        reasonCode: .backendGenerationTooOld,
                        detail: "required=\(generationFloor),actual=\(backend.backendGeneration)"
                    ))
                    continue
                }

                guard let hardware = environment.hardwareExecutionClass,
                      backend.hardwareClasses.contains(hardware)
                else {
                    rejected.append(.init(profileID: profile.id, backendID: backend.id, reasonCode: .backendHardwareMismatch, detail: environment.hardwareExecutionClass?.rawValue ?? hardwareDescriptor?.id ?? "unknown"))
                    continue
                }

                let hardwareCapabilities: Set<RuntimeCapability> = profile.baselineID == nil
                    ? []
                    : (hardwareDescriptor?.requiredCapabilities ?? [])
                let missingRequired = profile.requiredBackendCapabilities
                    .union(hardwareCapabilities)
                    .subtracting(backend.capabilities)
                guard missingRequired.isEmpty else {
                    rejected.append(.init(
                        profileID: profile.id,
                        backendID: backend.id,
                        reasonCode: .backendCapabilityMissing,
                        detail: missingRequired.map(\.rawValue).sorted().joined(separator: ",")
                    ))
                    continue
                }
                candidates.append(.init(
                    profile: profile,
                    backend: backend,
                    exactBuild: profile.exactBuildMatch(environment),
                    baseline: baseline
                ))
            }
        }

        guard !candidates.isEmpty else {
            return unsupported(identity: identity, rejected: rejected)
        }

        let selected: Candidate
        if let preferred = policy.preferredBackendID,
           let preferredCandidate = candidates
            .filter({ $0.backend.id == preferred })
            .sorted(by: candidateSort)
            .first
        {
            selected = preferredCandidate
        } else {
            selected = candidates.sorted(by: candidateSort).first!
        }

        let optionalMissing = selected.profile.optionalCapabilities.subtracting(selected.backend.capabilities)
        let activationCore: Set<RuntimeCapability> = [.activateRuntime, .verifyRuntime, .verifyBootstrap]
        let recoveryCore: Set<RuntimeCapability> = [.restoreRuntime, .reuseBootstrap, .verifyRuntime, .verifyBootstrap]

        let support: RuntimeSupportLevel
        if environment.hasInstalledBootstrap,
           !activationCore.isSubset(of: selected.backend.capabilities),
           recoveryCore.isSubset(of: selected.backend.capabilities),
           selected.profile.recoveryPolicy == .allowed
        {
            support = .recoveryOnly
        } else if activationCore.isSubset(of: selected.backend.capabilities) {
            if selected.backend.maturity == .experimental {
                support = .experimental
            } else if !optionalMissing.isEmpty {
                support = .partial
            } else {
                support = .supported
            }
        } else {
            support = .partial
        }

        return RuntimeResolution(
            environmentIdentity: identity,
            profileID: selected.profile.id,
            profileDisplayName: selected.profile.displayName,
            baselineID: selected.baseline?.id ?? selected.profile.baselineID,
            backendID: selected.backend.id,
            backendDisplayName: selected.backend.displayName,
            backendMaturity: selected.backend.maturity,
            backendGeneration: selected.backend.backendGeneration,
            supportLevel: support,
            capabilities: selected.backend.capabilities,
            missingCapabilities: optionalMissing,
            warnings: [],
            rejectedCandidates: rejected,
            resolutionGeneration: resolutionGeneration
        )
    }

    private static func candidateSort(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.backend.maturity.automaticRank != rhs.backend.maturity.automaticRank {
            return lhs.backend.maturity.automaticRank < rhs.backend.maturity.automaticRank
        }
        if lhs.exactBuild != rhs.exactBuild { return lhs.exactBuild && !rhs.exactBuild }
        if lhs.backend.backendGeneration != rhs.backend.backendGeneration {
            return lhs.backend.backendGeneration > rhs.backend.backendGeneration
        }
        if lhs.profile.id != rhs.profile.id { return lhs.profile.id < rhs.profile.id }
        return lhs.backend.id < rhs.backend.id
    }

    private static func unsupported(
        identity: String,
        rejected: [RuntimeRejectedCandidate]
    ) -> RuntimeResolution {
        RuntimeResolution(
            environmentIdentity: identity,
            profileID: nil,
            profileDisplayName: nil,
            baselineID: nil,
            backendID: nil,
            backendDisplayName: nil,
            backendMaturity: nil,
            backendGeneration: nil,
            supportLevel: .unsupported,
            capabilities: [],
            missingCapabilities: [],
            warnings: [],
            rejectedCandidates: rejected,
            resolutionGeneration: resolutionGeneration
        )
    }

    private static func environmentIdentity(_ environment: RuntimeEnvironment) -> String {
        [
            environment.deviceIdentifier,
            environment.osVersion,
            environment.osBuild,
            environment.hardwareSupportID ?? environment.hardwareExecutionClass?.rawValue ?? "unknown",
            environment.architecture,
            environment.upstreamBaselineID ?? "legacy",
            String(environment.environmentSchema),
        ].joined(separator: "|")
    }
}
