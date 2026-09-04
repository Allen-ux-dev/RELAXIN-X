import SwiftUI
import UIKit

extension HomeView {
    struct FailureView: View {
        let failure: EngineSession.Failure
        let resourceBundle: Bundle

        private enum Action: Hashable {
            case copy
        }

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(message)
                        .font(Theme.font)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    OptionList(
                        entries: [
                            OptionListItem(
                                id: Action.copy,
                                title: String(
                                    localized: "Copy Error Information",
                                    bundle: resourceBundle
                                )
                            ),
                        ],
                        style: .failure
                    ) { action in
                        switch action {
                        case .copy:
                            copyReport()
                        }
                    }
                    .padding(.leading, -OptionListLayout.markerGutter)
                    .padding(.top, 24)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.pagePadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.failureBackground.ignoresSafeArea())
        }

        private var message: String {
            """
            :(

            \(String(localized: "A problem has been detected and RELAXIN-X stopped the setup engine.", bundle: resourceBundle))
            \(String(localized: "Review the recovery guidance below before trying again.", bundle: resourceBundle))

            \(failure.report)

            \(String(localized: "Choose an option below.", bundle: resourceBundle))
            """
        }

        private func copyReport() {
            UIPasteboard.general.string = failure.report
            AppLog.info(Self.self, "failure report copied to clipboard")
        }
    }
}

#Preview("Engine Failure") {
    HomeView.FailureView(
        failure: EngineSession.Failure(
            report: """
            RELAXIN FAILURE REPORT
            ======================
            STOP CODE    RLX_ENGINE_3
            DOMAIN       com.aapl.relaxin.engine
            MESSAGE      The kernelcache could not be obtained.
            REASON       No local kernelcache was found and the download failed.
            RECOVERY     Check the network connection or include a matching kernelcache in the app bundle or Documents directory.

            ENGINE LOG
            [2/2] kernelcache acquisition [failed]
              libgrabkernel12: Range download failed

            DIAGNOSTICS
            stage=obtain_kernelcache
            downloaded=false
            """
        ),
        resourceBundle: .main
    )
}
