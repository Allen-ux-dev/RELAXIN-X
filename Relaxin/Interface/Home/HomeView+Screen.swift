import CoreGraphics
import Foundation

extension HomeView {
    enum Screen: Equatable {
        case home
        case advancedOptions
        case packageManagers
        case maintenance
        case credits
        case jetsamMultiplier
        case confirmation(ConfirmationAction)
        case engine

        enum TerminalSurface {
            case home
            case command(String)
            case credits
            case engine
        }

        var showsMenu: Bool {
            self != .engine
        }

        var terminalHeight: CGFloat {
            HomeContentLayout.terminalHeight
        }

        var terminalSurface: TerminalSurface {
            switch self {
            case .home:
                .home
            case .engine:
                .engine
            case .credits:
                .credits
            case .advancedOptions:
                .command("relaxin/advanced-options")
            case .packageManagers:
                .command("relaxin/advanced-options/package-managers")
            case .maintenance:
                .command("relaxin/maintenance")
            case .confirmation:
                .command("relaxin/confirm")
            case .jetsamMultiplier:
                .command("relaxin/advanced-options/jetsam-multiplier")
            }
        }

        var backDestination: Screen? {
            switch self {
            case .advancedOptions, .maintenance, .credits:
                .home
            case .packageManagers, .jetsamMultiplier:
                .advancedOptions
            case let .confirmation(action):
                switch action {
                case .removeJailbreak:
                    .home
                case .resetRelaxin:
                    .maintenance
                }
            case .home, .engine:
                nil
            }
        }

        func preferredMenuAction(
            configuration: JailbreakConfiguration
        ) -> MenuAction? {
            guard case .jetsamMultiplier = self else { return nil }
            return .setJetsamMultiplier(configuration.jetsamMultiplier)
        }

        func menuEntries(
            configuration: JailbreakConfiguration,
            interfaceMode: RelaxinInterfaceMode,
            canExportKernelcache: Bool,
            resourceBundle: Bundle
        ) -> [(action: MenuAction, title: String)] {
            switch self {
            case .home:
                var entries: [(MenuAction, String)] = [
                    (
                        .jailbreak,
                        configuration.removeJailbreakEnabled
                            ? String(localized: "Remove Jailbreak", bundle: resourceBundle)
                            : String(localized: "Start Jailbreak", bundle: resourceBundle)
                    ),
                    (
                        .environmentCheck,
                        String(localized: "Environment Check", bundle: resourceBundle)
                    ),
                    (
                        .advancedOptions,
                        String(localized: "Advanced Options", bundle: resourceBundle)
                    ),
                ]
                if interfaceMode.showsMaintenance {
                    entries.append(
                        (
                            .maintenance,
                            String(localized: "Maintenance Tools", bundle: resourceBundle)
                        )
                    )
                }
                entries.append(
                    (.credits, String(localized: "Credits", bundle: resourceBundle))
                )
                return entries
            case .advancedOptions:
                return [
                    (
                        .toggleOption(.tweakInjection),
                        optionTitle(
                            for: .tweakInjection,
                            configuration: configuration,
                            resourceBundle: resourceBundle
                        )
                    ),
                    (
                        .toggleOption(.appJIT),
                        optionTitle(
                            for: .appJIT,
                            configuration: configuration,
                            resourceBundle: resourceBundle
                        )
                    ),
                    (
                        .packageManagers,
                        String(localized: "Package Managers", bundle: resourceBundle)
                    ),
                    (
                        .stealthCompatibility,
                        String(localized: "Stealth Compatibility", bundle: resourceBundle)
                    ),
                    (
                        .runtimeBackendSettings,
                        String(localized: "Runtime Backend", bundle: resourceBundle)
                    ),
                    (
                        .jetsamMultiplier,
                        "\(String(localized: "Jetsam Multiplier", bundle: resourceBundle)): \(configuration.jetsamMultiplier.title(in: resourceBundle))"
                    ),
                    (
                        .toggleOption(.removeJailbreak),
                        optionTitle(
                            for: .removeJailbreak,
                            configuration: configuration,
                            resourceBundle: resourceBundle
                        )
                    ),
                    (.back, String(localized: "Back", bundle: resourceBundle)),
                ]
            case .packageManagers:
                return PackageManager.allCases.map { packageManager in
                    let selected = configuration.packageManagers.contains(packageManager)
                    let state = selected
                        ? String(localized: "ON", bundle: resourceBundle)
                        : String(localized: "OFF", bundle: resourceBundle)
                    let badge = switch packageManager {
                    case .sileo:
                        String(localized: "Recommended", bundle: resourceBundle)
                    case .zebra:
                        String(localized: "Experimental", bundle: resourceBundle)
                    }
                    return (
                        .togglePackageManager(packageManager),
                        "\(packageManager.displayName): \(state) — \(badge)"
                    )
                } + [(.back, String(localized: "Back", bundle: resourceBundle))]
            case .maintenance:
                var entries: [(MenuAction, String)] = []
                if interfaceMode.allowsFileExport {
                    entries.append(
                        (.exportLogs, String(localized: "Export Logs", bundle: resourceBundle))
                    )
                    if canExportKernelcache {
                        entries.append(
                            (
                                .exportKernelcache,
                                String(localized: "Export Kernelcache", bundle: resourceBundle)
                            )
                        )
                    }
                }
                entries.append(contentsOf: [
                    (
                        .confirm(.resetRelaxin),
                        String(localized: "Reset RELAXIN-X", bundle: resourceBundle)
                    ),
                    (.back, String(localized: "Back", bundle: resourceBundle)),
                ])
                return entries
            case .credits:
                var entries: [(MenuAction, String)] = []
                if interfaceMode.allowsExternalNavigation {
                    entries.append(contentsOf: [
                        (
                            .openOwnGoalStudioPicks,
                            String(localized: "OwnGoal Studio's Best", bundle: resourceBundle)
                        ),
                        (
                            .showSoftwareLicense,
                            String(localized: "Software License", bundle: resourceBundle)
                        ),
                    ])
                }
                entries.append(
                    (.back, String(localized: "Back", bundle: resourceBundle))
                )
                return entries
            case .jetsamMultiplier:
                return JailbreakConfiguration.JetsamMultiplier.allCases.map {
                    (.setJetsamMultiplier($0), $0.title(in: resourceBundle))
                } + [(.back, String(localized: "Back", bundle: resourceBundle))]
            case let .confirmation(action):
                let title = switch action {
                case .resetRelaxin:
                    String(localized: "Reset RELAXIN-X", bundle: resourceBundle)
                case .removeJailbreak:
                    String(localized: "Remove Jailbreak", bundle: resourceBundle)
                }
                return [
                    (
                        action.menuAction,
                        "\(String(localized: "Execute", bundle: resourceBundle)): \(title)"
                    ),
                    (.back, String(localized: "Back", bundle: resourceBundle)),
                ]
            case .engine:
                return []
            }
        }

        private func optionTitle(
            for option: ToggleOption,
            configuration: JailbreakConfiguration,
            resourceBundle: Bundle
        ) -> String {
            let state = option.isEnabled(in: configuration)
                ? String(localized: "ON", bundle: resourceBundle)
                : String(localized: "OFF", bundle: resourceBundle)
            return "\(option.title(in: resourceBundle)): \(state)"
        }
    }
}
