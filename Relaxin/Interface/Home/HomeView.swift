import Foundation
import SwiftUI

struct HomeView: View {
    let runtime: RelaxinRuntime

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) var openURL
    @StateObject var engineSession: EngineSession
    @State var screen = Screen.home
    @State var configuration: JailbreakConfiguration
    @State var alert: Presentation.Alert?
    @State var logExportState = LogExportState.idle
    @State var isPreparingPackageManagers = false
    @State var showsStealthCompatibility = false
    @State var showsRuntimeBackendSettings = false
    @State private var visibleCreditCharacterCount = 0
    @State private var terminalColumnCount = 32

    init(runtime: RelaxinRuntime) {
        self.runtime = runtime
        _engineSession = StateObject(wrappedValue: EngineSession(runtime: runtime))
        _configuration = State(
            initialValue: JailbreakConfiguration(defaults: runtime.defaults)
        )
    }

    var bootLogoUsesDarkAppearance: Bool {
        colorScheme == .dark
    }

    private var enabledToggleOptions: Set<ToggleOption> {
        Set(
            ToggleOption.allCases.filter {
                $0.isEnabled(in: configuration)
            }
        )
    }

    private var packageManagerSummary: String {
        PackageManager.allCases
            .filter(configuration.packageManagers.contains)
            .map(\.displayName)
            .joined(separator: " + ")
    }

    private var terminalText: String {
        switch screen.terminalSurface {
        case .home:
            RelaxinTerminalContent.home(
                isJailbroken: false,
                packageManagerSummary: packageManagerSummary,
                resourceBundle: runtime.resourceBundle
            )
        case let .command(command):
            RelaxinTerminalContent.command(
                command: command,
                output: engineSession.output,
                isJailbroken: false,
                terminalWidth: terminalColumnCount,
                resourceBundle: runtime.resourceBundle
            )
        case .credits:
            RelaxinTerminalContent.credits(
                visibleCharacterCount: visibleCreditCharacterCount,
                terminalWidth: terminalColumnCount,
                linksEnabled: runtime.interfaceMode.allowsExternalNavigation
            )
        case .engine:
            if case .idle = engineSession.phase {
                RelaxinTerminalContent.home(
                    isJailbroken: false,
                    packageManagerSummary: packageManagerSummary,
                    resourceBundle: runtime.resourceBundle
                )
            } else {
                RelaxinTerminalContent.running(
                    output: engineSession.output,
                    isJailbroken: false,
                    terminalWidth: terminalColumnCount,
                    resourceBundle: runtime.resourceBundle
                )
            }
        }
    }

    private var preferredTerminalHeight: CGFloat {
        guard screen == .credits else { return screen.terminalHeight }
        return HomeContentLayout.creditsTerminalHeight(
            lineCount: RelaxinCredits.lineCount(terminalWidth: terminalColumnCount)
        )
    }

    private var terminalAccessibleLinks: [TerminalPresenter.AccessibleLink] {
        guard screen == .credits else { return [] }
        return RelaxinCredits.accessibleLinks(
            linksEnabled: runtime.interfaceMode.allowsExternalNavigation
        )
    }

    private var rendersTerminalBackgroundActively: Bool {
        guard screen == .engine,
              !isShowingFailure,
              let hardwareExecutionClass = JailbreakTarget.current.hardwareExecutionClass
        else {
            return false
        }
        switch hardwareExecutionClass {
        case .pplDMAA12, .pplGFXA13:
            return false
        case .pplGFXA14M1, .gfxA15M2, .gfxA16, .sptmGFXA17:
            return true
        }
    }

    private var engineFailure: EngineSession.Failure? {
        guard case let .failed(failure) = engineSession.phase else { return nil }
        return failure
    }

    private var isShowingFailure: Bool {
        engineFailure != nil
    }

    private var primaryContent: some View {
        HomeContent(
            terminalText: terminalText,
            terminalAccessibleLinks: terminalAccessibleLinks,
            terminalHeight: preferredTerminalHeight,
            rendersTerminalBackgroundActively: rendersTerminalBackgroundActively,
            showsMenu: screen.showsMenu,
            menuItems: menuItems,
            preferredMenuAction: preferredMenuAction,
            secondaryMenuActions: [.back],
            shareItems: menuShareItems,
            loadingMenuActions: loadingMenuActions,
            disabledMenuActions: disabledMenuActions,
            isVolumeButtonInputEnabled: alert == nil,
            allowsOpeningTerminalLinks: runtime.interfaceMode.allowsExternalNavigation,
            onTerminalColumnCountChange: { terminalColumnCount = $0 },
            onSelectMenuItem: performMenuAction,
            onTerminalLongPress: {
                #if DEBUG
                    engineSession.postJailbreakSession.debugSetAvailable(true)
                #endif
            }
        )
    }

    @ViewBuilder private var presentedContent: some View {
        if #available(iOS 17.0, *) {
            if let failure = engineFailure {
                FailureView(
                    failure: failure,
                    resourceBundle: runtime.resourceBundle
                )
            } else {
                primaryContent
            }
        } else {
            ZStack {
                primaryContent
                    .allowsHitTesting(!isShowingFailure)
                    .accessibilityHidden(isShowingFailure)

                if let failure = engineFailure {
                    FailureView(
                        failure: failure,
                        resourceBundle: runtime.resourceBundle
                    )
                    .zIndex(1)
                }
            }
        }
    }

    private var showsVerifiedPostJailbreakContent: Bool {
        switch runtime.interfaceMode {
        case .full:
            return engineSession.environmentState == .activeHealthy
                || engineSession.environmentState == .activeDegraded
        case .lite:
            return engineSession.postJailbreakSession.isAvailable
        case .overlay:
            return false
        }
    }

    @ViewBuilder private var productContent: some View {
        if runtime.interfaceMode.showsPostJailbreakInterface,
           showsVerifiedPostJailbreakContent,
           !isShowingFailure
        {
            PostJailbreakHomeView(
                session: engineSession.postJailbreakSession,
                environment: runtime.postJailbreakEnvironment
            )
        } else {
            presentedContent
                .overlay(alignment: .topTrailing) {
                    if runtime.interfaceMode == .full, screen == .home {
                        EnvironmentStatusView(
                            state: engineSession.environmentState,
                            snapshot: engineSession.environmentSnapshot,
                            resourceBundle: runtime.resourceBundle
                        )
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                    }
                }
                .alert(item: $alert) { alert in
                    switch alert.kind {
                    case .notice:
                        SwiftUI.Alert(
                            title: Text(alert.title),
                            message: Text(alert.message),
                            dismissButton: .default(
                                Text(
                                    String(
                                        localized: "OK",
                                        bundle: runtime.resourceBundle
                                    )
                                )
                            )
                        )
                    case .jailbreakRemovalComplete:
                        SwiftUI.Alert(
                            title: Text(alert.title),
                            message: Text(alert.message),
                            dismissButton: .default(
                                Text(
                                    String(
                                        localized: "OK",
                                        bundle: runtime.resourceBundle
                                    )
                                )
                            ) {
                                suspendApplication()
                            }
                        )
                    }
                }
        }
    }

    var body: some View {
        productContent
            .sheet(isPresented: $showsStealthCompatibility) {
                NavigationStack {
                    StealthCompatibilityView(session: engineSession)
                }
            }
            .sheet(isPresented: $showsRuntimeBackendSettings) {
                NavigationStack {
                    RuntimeBackendSettingsView(session: engineSession)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { engineSession.packageManagerConfirmationDraft != nil },
                    set: { _ in }
                )
            ) {
                if let draft = engineSession.packageManagerConfirmationDraft {
                    PackageManagerInstallConfirmationView(
                        draft: draft,
                        resourceBundle: runtime.resourceBundle,
                        onToggle: engineSession.togglePendingPackageManager,
                        onCancel: engineSession.cancelPendingPackageManagers,
                        onConfirm: {
                            if let selection = engineSession.confirmPendingPackageManagers() {
                                configuration.packageManagers = selection
                            }
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .task {
                guard runtime.interfaceMode == .full else { return }
                await engineSession.refreshEnvironment()
                if engineSession.environmentState == .activeHealthy
                    || engineSession.environmentState == .activeDegraded
                {
                    engineSession.postJailbreakSession.refreshAvailability()
                }
            }
            .modifier(
                LightImpactFeedbackModifier(trigger: screen) { oldScreen, newScreen in
                    oldScreen != newScreen && newScreen.showsMenu
                }
            )
            .modifier(LightImpactFeedbackModifier(trigger: enabledToggleOptions))
        #if DEBUG
            .modifier(
                LightImpactFeedbackModifier(
                    trigger: engineSession.postJailbreakSession.isAvailable
                )
            )
        #endif
            .task(id: screen == .credits) {
                visibleCreditCharacterCount = 0
                guard screen == .credits else { return }

                var characterCount = 0
                while characterCount < RelaxinCredits.characterCount {
                    do {
                        try await Task.sleep(
                            for: .milliseconds(.random(in: 15 ... 35))
                        )
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    characterCount = min(
                        characterCount + .random(in: 1 ... 4),
                        RelaxinCredits.characterCount
                    )
                    visibleCreditCharacterCount = characterCount
                }
            }
    }
}

#Preview {
    NavigationStack {
        HomeView(runtime: .native)
    }
}
