import RelaxinEngine
import SwiftUI
import UIKit

extension HomeView {
    func startEngine() {
        startEngine(recoveryOperation: nil)
    }

    func startRecoveryEnvironment() {
        startEngine(recoveryOperation: .restoreEnvironment)
    }

    func repairCurrentEnvironment() {
        guard screen != .engine,
              case .idle = engineSession.phase,
              !isPreparingPackageManagers
        else {
            return
        }

        let runRepair = {
            engineSession.startTargetedRepair()
        }
        if #available(iOS 17.0, *) {
            withAnimation(.spring(duration: 0.5, bounce: 0, blendDuration: 0.25)) {
                screen = .engine
            } completion: {
                runRepair()
            }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 1, blendDuration: 0.25)) {
                screen = .engine
            }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                runRepair()
            }
        }
    }

    private func startEngine(recoveryOperation: RecoveryOperation?) {
        guard screen != .engine,
              case .idle = engineSession.phase,
              !isPreparingPackageManagers
        else {
            return
        }

        guard let snapshot = engineSession.environmentSnapshot,
              let resolution = snapshot.runtimeResolution
        else {
            alert = Presentation.Alert(
                title: String(localized: "Unsupported Target", bundle: runtime.resourceBundle),
                message: String(
                    localized: "A verified runtime profile and backend could not be resolved.",
                    bundle: runtime.resourceBundle
                )
            )
            return
        }

        var manifest: [RLXEngineManifestKey: String]
        do {
            manifest = try configuration.manifest(for: .current, resolution: resolution)
            manifest[.bootLogoDarkAppearanceKey] =
                bootLogoUsesDarkAppearance ? "true" : "false"
        } catch {
            let message = if let confirmationError = error as? JailbreakTarget.ConfirmationError {
                confirmationError.localizedDescription(in: runtime.resourceBundle)
            } else {
                error.localizedDescription
            }
            AppLog.error(Self.self, "target confirmation failed: \(message)")
            alert = Presentation.Alert(
                title: String(
                    localized: "Unsupported Target",
                    bundle: runtime.resourceBundle
                ),
                message: message
            )
            return
        }

        let removesJailbreak = configuration.removeJailbreakEnabled
        configuration.consumeRemoveJailbreakRequest()
        AppLog.info(Self.self, "target confirmed \(JailbreakTarget.current.logDescription)")

        guard recoveryOperation == nil,
              !removesJailbreak,
              configuration.packageManagers.contains(.zebra)
        else {
            launchEngine(
                manifest: manifest,
                removesJailbreak: removesJailbreak,
                recoveryOperation: recoveryOperation
            )
            return
        }

        isPreparingPackageManagers = true
        Task { @MainActor in
            defer { isPreparingPackageManagers = false }
            do {
                let zebraPackage = try await ZebraPackagePreflight(
                    cacheDirectory: runtime.cacheDirectory
                ).prepare()
                manifest[.zebraPackagePathKey] = zebraPackage.path
                AppLog.info(Self.self, "zebra preflight verified package=\(zebraPackage.lastPathComponent)")
                launchEngine(manifest: manifest, removesJailbreak: false, recoveryOperation: nil)
            } catch {
                AppLog.error(Self.self, "zebra preflight failed: \(error.localizedDescription)")
                alert = Presentation.Alert(
                    title: String(
                        localized: "Zebra Unavailable",
                        bundle: runtime.resourceBundle
                    ),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func launchEngine(
        manifest: [RLXEngineManifestKey: String],
        removesJailbreak: Bool,
        recoveryOperation: RecoveryOperation?
    ) {
        let runEngine = {
            let completion = {
                guard removesJailbreak else { return }
                alert = .jailbreakRemovalComplete(in: runtime.resourceBundle)
            }
            if let recoveryOperation {
                engineSession.startRecovery(
                    operation: recoveryOperation,
                    manifest: manifest,
                    onSuccess: completion
                )
            } else {
                engineSession.start(manifest: manifest, onSuccess: completion)
            }
        }

        if #available(iOS 17.0, *) {
            withAnimation(.spring(duration: 0.5, bounce: 0, blendDuration: 0.25)) {
                screen = .engine
            } completion: {
                runEngine()
            }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 1, blendDuration: 0.25)) {
                screen = .engine
            }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                runEngine()
            }
        }
    }

    func suspendApplication() {
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }
}
