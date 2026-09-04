import SwiftUI
import UIKit

struct RootView: View {
    let runtime: RelaxinRuntime

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
        .font(Theme.font)
        .dynamicTypeSize(.medium)
        .tint(Theme.accent)
        .frame(minWidth: minSize?.width, minHeight: minSize?.height)
    }

    @ViewBuilder private var content: some View {
        switch runtime.interfaceMode {
        case .full, .overlay:
            HomeView(runtime: runtime)
        case .lite:
            PostJailbreakRootContent(runtime: runtime)
        }
    }

    /// Prevents resizable iPad windows from clipping the terminal column.
    private var minSize: CGSize? {
        UIDevice.current.userInterfaceIdiom == .pad
            ? CGSize(width: 560, height: 760)
            : nil
    }
}

private struct PostJailbreakRootContent: View {
    let environment: PostJailbreakEnvironment
    @StateObject private var session: PostJailbreakSession

    init(runtime: RelaxinRuntime) {
        let environment = runtime.postJailbreakEnvironment
        self.environment = environment
        _session = StateObject(
            wrappedValue: PostJailbreakSession(environment: environment)
        )
    }

    var body: some View {
        PostJailbreakHomeView(session: session, environment: environment)
            .task {
                session.refreshAvailability()
            }
    }
}

#Preview {
    RootView(runtime: .native)
}

#Preview("Overlay") {
    RootView(
        runtime: RelaxinRuntime(
            interfaceMode: .overlay,
            environment: .default,
            defaultsSuiteName: nil,
            additionalBootstrapPackageResourceNames: []
        )
    )
}
