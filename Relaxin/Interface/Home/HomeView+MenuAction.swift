import Foundation

extension HomeView {
    enum ToggleOption: CaseIterable, Hashable {
        case tweakInjection
        case appJIT
        case removeJailbreak

        func title(in resourceBundle: Bundle) -> String {
            switch self {
            case .tweakInjection:
                String(localized: "Tweak Injection", bundle: resourceBundle)
            case .appJIT:
                String(localized: "Allow JIT in Apps", bundle: resourceBundle)
            case .removeJailbreak:
                String(localized: "Remove Jailbreak", bundle: resourceBundle)
            }
        }

        private var valueKeyPath: WritableKeyPath<JailbreakConfiguration, Bool> {
            switch self {
            case .tweakInjection:
                \JailbreakConfiguration.tweakInjectionEnabled
            case .appJIT:
                \JailbreakConfiguration.appJITEnabled
            case .removeJailbreak:
                \JailbreakConfiguration.removeJailbreakEnabled
            }
        }

        func isEnabled(in configuration: JailbreakConfiguration) -> Bool {
            configuration[keyPath: valueKeyPath]
        }

        func toggle(in configuration: inout JailbreakConfiguration) {
            configuration[keyPath: valueKeyPath].toggle()
        }
    }

    enum ConfirmationAction: Hashable {
        case removeJailbreak
        case resetRelaxin

        var menuAction: MenuAction {
            switch self {
            case .removeJailbreak:
                .removeJailbreak
            case .resetRelaxin:
                .resetRelaxin
            }
        }
    }

    enum MenuAction: Hashable {
        case jailbreak
        case restoreEnvironment
        case repairEnvironment
        case environmentCheck
        case stealthCompatibility
        case runtimeBackendSettings
        case advancedOptions
        case maintenance
        case credits
        case openOwnGoalStudioPicks
        case showSoftwareLicense
        case toggleOption(ToggleOption)
        case packageManagers
        case togglePackageManager(PackageManager)
        case jetsamMultiplier
        case setJetsamMultiplier(JailbreakConfiguration.JetsamMultiplier)
        case resetRelaxin
        case exportKernelcache
        case exportLogs
        case removeJailbreak
        case confirm(ConfirmationAction)
        case back
    }
}
