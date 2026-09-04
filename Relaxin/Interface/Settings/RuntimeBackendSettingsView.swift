import SwiftUI

struct RuntimeBackendSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: EngineSession

    private static let recommendedSelection = ""

    var body: some View {
        Form {
            Section {
                if let resolution = session.environmentSnapshot?.runtimeResolution,
                   resolution.isResolved
                {
                    LabeledContent(
                        localized("Runtime Profile"),
                        value: resolution.profileDisplayName ?? resolution.profileID ?? localized("Unavailable")
                    )
                    LabeledContent(
                        localized("Runtime Backend"),
                        value: resolution.backendDisplayName ?? resolution.backendID ?? localized("Unavailable")
                    )
                    LabeledContent(
                        localized("Support Level"),
                        value: supportTitle(resolution.supportLevel)
                    )
                    LabeledContent(
                        localized("Capabilities"),
                        value: resolution.capabilities.map(\.rawValue).sorted().joined(separator: ", ")
                    )
                } else {
                    Text(localized("No compatible runtime profile and backend could be resolved."))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(localized("Current Runtime"))
            }

            Section {
                Picker(
                    localized("Backend Selection"),
                    selection: Binding(
                        get: { visiblePreferredBackendID },
                        set: { selection in
                            Task {
                                await session.setPreferredRuntimeBackendID(
                                    selection.isEmpty ? nil : selection
                                )
                            }
                        }
                    )
                ) {
                    Text(localized("Recommended"))
                        .tag(Self.recommendedSelection)
                    ForEach(visibleBackends, id: \.id) { backend in
                        Text(backendLabel(backend)).tag(backend.id)
                    }
                }

                Toggle(
                    localized("Enable Experimental Backends"),
                    isOn: Binding(
                        get: { session.runtimeBackendPolicy.experimentalEnabled },
                        set: { enabled in
                            Task {
                                await session.setRuntimeBackendExperimentalEnabled(enabled)
                            }
                        }
                    )
                )
            } header: {
                Text(localized("Developer Runtime Policy"))
            } footer: {
                Text(
                    localized(
                        "Backend preferences never bypass compatibility checks. Recommended selects the best eligible stable backend automatically."
                    )
                )
            }
        }
        .navigationTitle(localized("Runtime Backend"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("Done")) { dismiss() }
            }
        }
    }

    private var visibleBackends: [RuntimeBackendDescriptor] {
        RuntimeBackendRegistry.production
            .filter { backend in
                backend.maturity != .experimental || session.runtimeBackendPolicy.experimentalEnabled
            }
            .sorted { lhs, rhs in
                if lhs.maturity != rhs.maturity {
                    return lhs.maturity.automaticRank < rhs.maturity.automaticRank
                }
                return lhs.displayName < rhs.displayName
            }
    }

    private var visiblePreferredBackendID: String {
        guard let preferredBackendID = session.runtimeBackendPolicy.preferredBackendID,
              visibleBackends.contains(where: { $0.id == preferredBackendID })
        else {
            return Self.recommendedSelection
        }
        return preferredBackendID
    }

    private func backendLabel(_ backend: RuntimeBackendDescriptor) -> String {
        let maturity = switch backend.maturity {
        case .stable:
            localized("Stable")
        case .experimental:
            localized("Experimental")
        case .legacy:
            localized("Legacy")
        }
        return "\(backend.displayName) — \(maturity)"
    }

    private func supportTitle(_ level: RuntimeSupportLevel) -> String {
        switch level {
        case .supported:
            localized("Supported")
        case .experimental:
            localized("Experimental")
        case .partial:
            localized("Partial Support")
        case .recoveryOnly:
            localized("Recovery Only")
        case .unsupported:
            localized("Unsupported")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: session.runtime.resourceBundle)
    }
}
