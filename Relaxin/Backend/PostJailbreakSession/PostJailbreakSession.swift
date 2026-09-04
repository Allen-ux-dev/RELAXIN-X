import Combine
import Foundation
import RelaxinPostJailbreak

@MainActor
final class PostJailbreakSession: ObservableObject {
    typealias ReinstallSileoAction = @MainActor (
        _ output: @escaping (String) -> Void
    ) async throws -> Void

    @Published private(set) var isAvailable = false
    @Published private(set) var runtimeOptions = RuntimeOptions()
    @Published private(set) var output: [TerminalOutputLine] = []
    @Published private(set) var isPerformingAction = false

    let environment: PostJailbreakEnvironment
    private let controller: RLXPostJailbreakController
    private let reinstallSileoAction: ReinstallSileoAction?
    #if DEBUG
        private var debugAvailableOverride: Bool?
    #endif

    init(
        environment: PostJailbreakEnvironment,
        controller: RLXPostJailbreakController,
        reinstallSileo: ReinstallSileoAction? = nil
    ) {
        self.environment = environment
        self.controller = controller
        reinstallSileoAction = reinstallSileo
        switch environment.interfaceMode {
        case .full:
            isAvailable = controller.hasActiveRootHideRuntime()
        case .lite:
            isAvailable = true
        case .overlay:
            isAvailable = false
        }
    }

    convenience init(environment: PostJailbreakEnvironment) {
        self.init(
            environment: environment,
            controller: RLXPostJailbreakController(
                resourceBundle: environment.resourceBundle
            )
        )
    }

    var canReinstallSileo: Bool {
        environment.interfaceMode.allowsSileoReinstallation
            && reinstallSileoAction != nil
    }

    func refreshAvailability() {
        #if DEBUG
            if let debugAvailableOverride {
                isAvailable = debugAvailableOverride
                return
            }
        #endif
        isAvailable = controller.isAvailable()
        if isAvailable {
            refreshRuntimeOptions()
        }
    }

    func refreshRuntimeOptions() {
        guard isAvailable else { return }
        runtimeOptions = RuntimeOptions(
            tweakInjectionEnabled: controller.tweakInjectionEnabled(),
            appJITEnabled: controller.appJITEnabled()
        )
    }

    func setTweakInjectionEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        controller.setTweakInjectionEnabled(enabled)
        runtimeOptions.tweakInjectionEnabled = enabled
    }

    func setAppJITEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        controller.setAppJITEnabled(enabled)
        runtimeOptions.appJITEnabled = enabled
    }

    func compatibilityProfileEnabled(bundleIdentifier: String) -> Bool {
        guard isAvailable else { return false }
        return controller.compatibilityProfileEnabled(bundleIdentifier: bundleIdentifier)
    }

    func setCompatibilityProfile(
        bundleIdentifier: String,
        enabled: Bool
    ) async throws {
        try await controller.perform(
            action: .setCompatibilityProfile,
            arguments: [
                .bundleIdentifierKey: bundleIdentifier,
                .compatibilityEnabledKey: enabled ? "true" : "false",
            ],
            output: nil
        )
        refreshAvailability()
    }

    func perform(_ action: Action) {
        guard isAvailable, !isPerformingAction else { return }
        performOperation { [controller] outputHandler in
            try await controller.perform(
                action: action.postJailbreakAction,
                arguments: action.postJailbreakArguments,
                output: outputHandler
            )
        }
    }

    func reinstallSileo() {
        guard canReinstallSileo, let reinstallSileoAction else { return }
        performOperation(reinstallSileoAction)
    }

    private func performOperation(_ operation: @escaping ReinstallSileoAction) {
        guard isAvailable, !isPerformingAction else { return }
        isPerformingAction = true
        Task { [self] in
            defer { isPerformingAction = false }
            do {
                let outputHandler: (String) -> Void = { message in
                    if Thread.isMainThread {
                        self.append(
                            TerminalOutputLine(label: message, status: .info)
                        )
                    } else {
                        DispatchQueue.main.sync {
                            self.append(
                                TerminalOutputLine(label: message, status: .info)
                            )
                        }
                    }
                }
                try await operation(outputHandler)
                refreshAvailability()
            } catch {
                append(
                    TerminalOutputLine(
                        label: error.localizedDescription,
                        status: .failed
                    )
                )
            }
        }
    }

    private func append(_ line: TerminalOutputLine) {
        output.append(line)
    }

    #if DEBUG
        func debugSetAvailable(_ value: Bool) {
            debugAvailableOverride = value
            isAvailable = value
            AppLog.info(Self.self, "debug post-jailbreak available=\(value ? 1 : 0)")
        }
    #endif
}

extension PostJailbreakSession {
    enum Action {
        case restartSpringBoard
        case restartUserspace(darkAppearance: Bool)
        case refreshJailbreakApps
        case resetMobilePassword
        case removeJailbreak
    }

    struct RuntimeOptions: Equatable {
        var tweakInjectionEnabled = true
        var appJITEnabled = true
    }
}

private extension PostJailbreakSession.Action {
    var postJailbreakAction: RLXPostJailbreakAction {
        switch self {
        case .restartSpringBoard:
            .restartSpringBoard
        case .restartUserspace:
            .restartUserspace
        case .refreshJailbreakApps:
            .refreshJailbreakApps
        case .resetMobilePassword:
            .resetMobilePassword
        case .removeJailbreak:
            .removeJailbreak
        }
    }

    var postJailbreakArguments: [RLXPostJailbreakActionArgumentKey: String]? {
        guard case let .restartUserspace(darkAppearance) = self else {
            return nil
        }
        return [
            .bootLogoDarkAppearanceKey: darkAppearance ? "true" : "false",
        ]
    }
}
