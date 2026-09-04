import SwiftUI

struct StealthCompatibilityView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: EngineSession
    @State private var bundleIdentifier = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section(localized("Stealth Compatibility")) {
                LabeledContent(localized("Environment"), value: healthLabel)
                if session.stealthHealth.overall == .suspended {
                    Text(localized("Compatibility profiles are suspended until the jailbreak runtime is restored."))
                        .foregroundStyle(.secondary)
                }
                if session.stealthHealth.overall == .needsVerification {
                    Text(localized("Needs Review"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Applications")) {
                if session.stealthProfiles.isEmpty {
                    Text(localized("No application profiles are configured."))
                        .foregroundStyle(.secondary)
                }
                ForEach(session.stealthProfiles) { profile in
                    profileRow(profile)
                }
            }

            Section(localized("Add Application")) {
                TextField(localized("Bundle Identifier"), text: $bundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(localized("Add Compatibility Profile")) {
                    let identifier = bundleIdentifier
                    Task {
                        do {
                            try await session.setStealthProfileMode(
                                .automatic,
                                bundleIdentifier: identifier
                            )
                            bundleIdentifier = ""
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                Text(
                    localized(
                        "Compatibility profiles reduce accidental jailbreak-environment exposure for ordinary apps. Management and development components stay outside compatibility isolation."
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(localized("Stealth Compatibility"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localized("Done")) { dismiss() }
            }
        }
        .alert(
            localized("Compatibility Profile"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(localized("OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: AppStealthProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.bundleIdentifier)
                    .font(.footnote.monospaced())
                Spacer()
                if StealthProfileResolver.managementBundleIdentifiers.contains(profile.bundleIdentifier) {
                    Image(systemName: "lock.fill")
                        .accessibilityLabel(localized("Protected management application"))
                }
            }

            Picker(
                localized("Mode"),
                selection: Binding(
                    get: { profile.mode },
                    set: { mode in
                        Task {
                            do {
                                try await session.setStealthProfileMode(
                                    mode,
                                    bundleIdentifier: profile.bundleIdentifier
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            ) {
                ForEach(StealthProfileMode.allCases, id: \.self) { mode in
                    Text(mode.title(in: session.runtime.resourceBundle)).tag(mode)
                }
            }
            .disabled(StealthProfileResolver.managementBundleIdentifiers.contains(profile.bundleIdentifier))

            if session.stealthHealth.affectedBundleIdentifiers.contains(profile.bundleIdentifier) {
                Button(localized("Repair Compatibility")) {
                    Task {
                        do {
                            try await session.repairStealthProfile(
                                bundleIdentifier: profile.bundleIdentifier
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Text(localized("Needs Review"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var healthLabel: String {
        switch session.stealthHealth.overall {
        case .ready:
            localized("Ready")
        case .suspended:
            localized("Suspended")
        case .degraded:
            localized("Degraded")
        case .needsVerification:
            localized("Needs Review")
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: session.runtime.resourceBundle)
    }
}

private extension StealthProfileMode {
    func title(in resourceBundle: Bundle) -> String {
        switch self {
        case .automatic:
            String(localized: "Automatic", bundle: resourceBundle)
        case .compatibility:
            String(localized: "Compatibility", bundle: resourceBundle)
        case .developer:
            String(localized: "Developer", bundle: resourceBundle)
        case .disabled:
            String(localized: "Disabled", bundle: resourceBundle)
        case .needsReview:
            String(localized: "Needs Review", bundle: resourceBundle)
        }
    }
}
