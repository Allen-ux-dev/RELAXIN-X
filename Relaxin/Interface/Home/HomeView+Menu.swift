import Foundation

extension HomeView {
    private static let ownGoalStudioPicksURL = URL(string: "https://owngoal.dev")!

    var menuItems: [OptionListItem<MenuAction>] {
        var entries = screen.menuEntries(
            configuration: configuration,
            interfaceMode: runtime.interfaceMode,
            canExportKernelcache: runtime.interfaceMode.allowsFileExport
                && kernelcacheExportURL != nil,
            resourceBundle: runtime.resourceBundle
        )

        guard screen == .home else {
            return entries.map { entry in
                OptionListItem(id: entry.action, title: entry.title)
            }
        }

        if let jailbreakIndex = entries.firstIndex(where: { $0.action == .jailbreak }) {
            entries[jailbreakIndex] = (.jailbreak, jailbreakMenuTitle)
        }
        if let environmentIndex = entries.firstIndex(where: { $0.action == .environmentCheck }) {
            entries[environmentIndex] = (.environmentCheck, environmentCheckMenuTitle)
            if let recoveryMenuAction {
                entries.insert(recoveryMenuAction, at: environmentIndex + 1)
            }
        }

        return entries.map { entry in
            OptionListItem(id: entry.action, title: entry.title)
        }
    }

    var canStartHomeJailbreak: Bool {
        guard !configuration.removeJailbreakEnabled,
              engineSession.environmentState == .clean,
              case .idle = engineSession.phase,
              !isPreparingPackageManagers
        else {
            return false
        }
        return runtimeSupportsPrimaryAction(.startJailbreak)
    }

    var disabledMenuActions: Set<MenuAction> {
        guard screen == .home,
              !configuration.removeJailbreakEnabled,
              !isPreparingPackageManagers,
              !canStartHomeJailbreak
        else {
            return []
        }
        return [.jailbreak]
    }

    private var jailbreakMenuTitle: String {
        if configuration.removeJailbreakEnabled {
            return String(localized: "Remove Jailbreak", bundle: runtime.resourceBundle)
        }

        let title = String(localized: "Start Jailbreak", bundle: runtime.resourceBundle)
        guard !canStartHomeJailbreak, !isPreparingPackageManagers else { return title }
        return "\(title) · \(jailbreakDisabledReason)"
    }

    private var environmentCheckMenuTitle: String {
        let title = String(localized: "Environment Check", bundle: runtime.resourceBundle)
        return "\(title) · \(environmentStatusTitle)"
    }

    private var environmentStatusTitle: String {
        switch engineSession.environmentState {
        case .inspecting:
            String(localized: "Checking Environment", bundle: runtime.resourceBundle)
        case .unsupported:
            String(localized: "Unsupported Environment", bundle: runtime.resourceBundle)
        case .conflicting:
            String(localized: "Conflicting Environment", bundle: runtime.resourceBundle)
        case .clean:
            String(localized: "Environment Ready", bundle: runtime.resourceBundle)
        case .installedInactive:
            String(localized: "Runtime Inactive", bundle: runtime.resourceBundle)
        case .activating:
            String(localized: "Restoring Environment", bundle: runtime.resourceBundle)
        case .activeHealthy:
            String(localized: "Environment Healthy", bundle: runtime.resourceBundle)
        case .activeDegraded:
            String(localized: "Environment Degraded", bundle: runtime.resourceBundle)
        case .repairRequired:
            String(localized: "Environment Requires Repair", bundle: runtime.resourceBundle)
        }
    }

    private var jailbreakDisabledReason: String {
        guard engineSession.environmentState == .clean else {
            return environmentStatusTitle
        }
        return String(localized: "Unsupported Target", bundle: runtime.resourceBundle)
    }

    private var recoveryMenuAction: (MenuAction, String)? {
        guard !configuration.removeJailbreakEnabled else { return nil }
        let action = EnvironmentPrimaryAction.resolve(state: engineSession.environmentState)
        guard runtimeSupportsPrimaryAction(action) else { return nil }
        switch action {
        case .restoreEnvironment:
            return (
                .restoreEnvironment,
                String(localized: "Restore Jailbreak Environment", bundle: runtime.resourceBundle)
            )
        case .repairEnvironment:
            return (
                .repairEnvironment,
                String(localized: "Repair Current Environment", bundle: runtime.resourceBundle)
            )
        case .startJailbreak, .none:
            return nil
        }
    }

    private func runtimeSupportsPrimaryAction(_ action: EnvironmentPrimaryAction) -> Bool {
        guard let resolution = engineSession.environmentSnapshot?.runtimeResolution else {
            return false
        }
        let requirements: Set<RuntimeCapability>
        switch action {
        case .startJailbreak:
            requirements = RuntimeOperationRequirements.freshInstall(
                packageManagerSelected: !configuration.packageManagers.isEmpty
            )
        case .restoreEnvironment:
            requirements = RuntimeOperationRequirements.restore
        case .repairEnvironment:
            requirements = RuntimeOperationRequirements.repair(packageManager: true)
        case .none:
            return true
        }
        return resolution.supports(requirements)
    }

    var preferredMenuAction: MenuAction? {
        screen.preferredMenuAction(configuration: configuration)
    }

    var menuShareItems: [MenuAction: URL] {
        switch screen {
        case .maintenance:
            guard runtime.interfaceMode.allowsFileExport else { return [:] }
            var items: [MenuAction: URL] = logExportState.archiveURL.map {
                [.exportLogs: $0]
            } ?? [:]
            if let kernelcacheExportURL {
                items[.exportKernelcache] = kernelcacheExportURL
            }
            return items
        case .credits:
            guard runtime.interfaceMode.allowsExternalNavigation else {
                return [:]
            }
            return softwareLicenseURL.map { [.showSoftwareLicense: $0] } ?? [:]
        case .home, .advancedOptions, .packageManagers, .jetsamMultiplier, .confirmation,
             .engine:
            return [:]
        }
    }

    var loadingMenuActions: Set<MenuAction> {
        var actions: Set<MenuAction> = isPreparingPackageManagers ? [.jailbreak, .restoreEnvironment] : []
        if screen == .home, engineSession.environmentState == .inspecting {
            actions.insert(.environmentCheck)
        }
        if runtime.interfaceMode.allowsFileExport,
           screen == .maintenance,
           logExportState.isPreparing
        {
            actions.insert(.exportLogs)
        }
        return actions
    }

    func performMenuAction(_ action: MenuAction) {
        switch action {
        case .jailbreak:
            guard !configuration.removeJailbreakEnabled else {
                screen = .confirmation(.removeJailbreak)
                return
            }
            startEngine()
        case .restoreEnvironment:
            startRecoveryEnvironment()
        case .repairEnvironment:
            repairCurrentEnvironment()
        case .environmentCheck:
            Task { @MainActor in
                await engineSession.refreshEnvironment()
                alert = .environmentCheck(
                    state: engineSession.environmentState,
                    stealthHealth: engineSession.stealthHealth,
                    in: runtime.resourceBundle
                )
            }
        case .stealthCompatibility:
            showsStealthCompatibility = true
        case .runtimeBackendSettings:
            showsRuntimeBackendSettings = true
        case .advancedOptions:
            screen = .advancedOptions
        case .packageManagers:
            screen = .packageManagers
        case .maintenance:
            guard runtime.interfaceMode.showsMaintenance else { return }
            if runtime.interfaceMode.allowsFileExport {
                prepareLogExport()
            }
            screen = .maintenance
        case .credits:
            screen = .credits
        case .openOwnGoalStudioPicks:
            guard runtime.interfaceMode.allowsExternalNavigation else { return }
            openURL(Self.ownGoalStudioPicksURL)
        case .showSoftwareLicense:
            guard runtime.interfaceMode.allowsExternalNavigation else { return }
            showSoftwareLicenseUnavailable()
        case let .toggleOption(option):
            option.toggle(in: &configuration)
        case let .togglePackageManager(packageManager):
            guard configuration.packageManagers.toggle(packageManager) else {
                alert = Presentation.Alert(
                    title: String(
                        localized: "Package Manager Required",
                        bundle: runtime.resourceBundle
                    ),
                    message: String(
                        localized: "Keep at least one package manager selected.",
                        bundle: runtime.resourceBundle
                    )
                )
                return
            }
        case .jetsamMultiplier:
            screen = .jetsamMultiplier
        case let .setJetsamMultiplier(multiplier):
            configuration.jetsamMultiplier = multiplier
            screen = .advancedOptions
        case .resetRelaxin:
            resetRelaxin()
        case .exportLogs:
            guard runtime.interfaceMode.allowsFileExport else { return }
            prepareLogExport()
        case .exportKernelcache:
            guard runtime.interfaceMode.allowsFileExport else { return }
            showKernelcacheUnavailable()
        case let .confirm(action):
            screen = .confirmation(action)
        case .removeJailbreak:
            startEngine()
        case .back:
            if let destination = screen.backDestination {
                screen = destination
            }
        }
    }
}
