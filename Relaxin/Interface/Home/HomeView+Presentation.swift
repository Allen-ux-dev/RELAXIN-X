import Foundation

extension HomeView {
    enum Presentation {
        struct Alert: Identifiable {
            enum Kind {
                case notice
                case jailbreakRemovalComplete
            }

            let title: String
            let message: String
            var kind = Kind.notice

            var id: String {
                "\(kind)\0\(title)\0\(message)"
            }

            static func environmentCheck(
                state: JailbreakEnvironmentState,
                stealthHealth: StealthHealth,
                in resourceBundle: Bundle
            ) -> Alert {
                let environment = switch state {
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
                let stealth = switch stealthHealth.overall {
                case .ready:
                    String(localized: "Stealth Compatibility", bundle: resourceBundle) + ": "
                        + String(localized: "Ready", bundle: resourceBundle)
                case .suspended:
                    String(localized: "Stealth Compatibility Suspended", bundle: resourceBundle)
                case .degraded:
                    String(localized: "Stealth Compatibility", bundle: resourceBundle) + ": "
                        + String(localized: "Degraded", bundle: resourceBundle)
                case .needsVerification:
                    String(localized: "Compatibility Profiles Need Revalidation", bundle: resourceBundle)
                }
                return Alert(
                    title: String(localized: "Environment Check", bundle: resourceBundle),
                    message: "\(environment)\n\(stealth)"
                )
            }

            static func jailbreakRemovalComplete(in resourceBundle: Bundle) -> Alert {
                Alert(
                    title: String(
                        localized: "Jailbreak Removal Complete",
                        bundle: resourceBundle
                    ),
                    message: String(
                        localized: "Jailbreak removal is complete. Tap OK to close RELAXIN-X.",
                        bundle: resourceBundle
                    ),
                    kind: .jailbreakRemovalComplete
                )
            }
        }
    }
}
