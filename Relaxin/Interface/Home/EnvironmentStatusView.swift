import SwiftUI

struct EnvironmentStatusView: View {
    let state: JailbreakEnvironmentState
    let snapshot: EnvironmentSnapshot?
    let resourceBundle: Bundle

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(state == .activeHealthy ? 1 : 0.55)
                Text(title)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }

            if let resolution = snapshot?.runtimeResolution, resolution.isResolved {
                Text(runtimeSummary(resolution))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(capabilitySummary(resolution.capabilities))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.background.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.foreground.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch state {
        case .inspecting:
            String(localized: "Checking Environment", bundle: resourceBundle)
        case .unsupported:
            String(localized: "Unsupported Environment", bundle: resourceBundle)
        case .conflicting:
            String(localized: "Conflicting Environment", bundle: resourceBundle)
        case .clean:
            String(localized: "Environment Ready", bundle: resourceBundle)
        case .installedInactive:
            String(localized: "Runtime Inactive", bundle: resourceBundle)
        case .activating:
            String(localized: "Restoring Environment", bundle: resourceBundle)
        case .activeHealthy:
            String(localized: "Environment Healthy", bundle: resourceBundle)
        case .activeDegraded:
            String(localized: "Environment Degraded", bundle: resourceBundle)
        case .repairRequired:
            String(localized: "Environment Requires Repair", bundle: resourceBundle)
        }
    }

    private func runtimeSummary(_ resolution: RuntimeResolution) -> String {
        let profile = resolution.profileDisplayName ?? resolution.profileID ?? "—"
        let backend = resolution.backendDisplayName ?? resolution.backendID ?? "—"
        return "\(profile) · \(backend) · \(supportTitle(resolution.supportLevel))"
    }

    private func capabilitySummary(_ capabilities: Set<RuntimeCapability>) -> String {
        let activation = capabilities.contains(.activateRuntime)
            ? String(localized: "Activation Ready", bundle: resourceBundle)
            : String(localized: "Activation Unavailable", bundle: resourceBundle)
        let recovery = capabilities.contains(.restoreRuntime)
            ? String(localized: "Recovery Ready", bundle: resourceBundle)
            : String(localized: "Recovery Unavailable", bundle: resourceBundle)
        let repair = capabilities.contains(.repairPackageManager)
            ? String(localized: "Repair Ready", bundle: resourceBundle)
            : String(localized: "Repair Unavailable", bundle: resourceBundle)
        return "\(activation) · \(recovery) · \(repair)"
    }

    private func supportTitle(_ supportLevel: RuntimeSupportLevel) -> String {
        switch supportLevel {
        case .supported:
            String(localized: "Supported", bundle: resourceBundle)
        case .experimental:
            String(localized: "Experimental", bundle: resourceBundle)
        case .partial:
            String(localized: "Partial Support", bundle: resourceBundle)
        case .recoveryOnly:
            String(localized: "Recovery Only", bundle: resourceBundle)
        case .unsupported:
            String(localized: "Unsupported", bundle: resourceBundle)
        }
    }
}
