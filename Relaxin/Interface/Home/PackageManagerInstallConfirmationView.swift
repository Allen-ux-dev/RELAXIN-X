import SwiftUI

struct PackageManagerInstallConfirmationView: View {
    let draft: PackageManagerConfirmationDraft
    let resourceBundle: Bundle
    let onToggle: (PackageManager) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PackageManager.allCases, id: \.self) { packageManager in
                        Button {
                            onToggle(packageManager)
                        } label: {
                            HStack {
                                Text(packageManager.displayName)
                                Spacer()
                                Image(systemName: draft.selection.contains(packageManager)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(
                        String(
                            localized: "Choose Package Managers",
                            bundle: resourceBundle
                        )
                    )
                } footer: {
                    Text(
                        String(
                            localized: "The selected managers will be installed now. Keep at least one selected.",
                            bundle: resourceBundle
                        )
                    )
                }

                Section {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Text(
                            String(
                                localized: "Cancel Jailbreak",
                                bundle: resourceBundle
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        onConfirm()
                    } label: {
                        Text(
                            String(
                                localized: "Confirm and Continue",
                                bundle: resourceBundle
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(
                String(
                    localized: "Package Manager Confirmation",
                    bundle: resourceBundle
                )
            )
        }
        .interactiveDismissDisabled()
    }
}
