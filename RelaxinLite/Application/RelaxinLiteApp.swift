import Foundation
import SwiftUI

struct RelaxinLiteApp: App {
    private let environment: PostJailbreakEnvironment

    init() {
        let environment = PostJailbreakEnvironment(
            interfaceMode: .lite,
            resourceBundle: .main
        )
        self.environment = environment

        let dataDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("RelaxinLite", isDirectory: true)
        AppLog.bootstrap(dataDirectory: dataDirectory)
        AppLog.connectPostJailbreakLogging()
        AppLog.info(
            Self.self,
            "app init version=\(AppInfo.version(in: environment.resourceBundle)) "
                + "build=\(AppInfo.build(in: environment.resourceBundle)) arch=\(AppInfo.arch)"
        )
        TerminalCharacterBackgroundImage.prepare()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RelaxinLiteRootView(environment: environment)
        }
        .commandsReplaced {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
