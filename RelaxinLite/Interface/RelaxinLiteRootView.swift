import SwiftUI
import UIKit

struct RelaxinLiteRootView: View {
    let environment: PostJailbreakEnvironment
    @StateObject private var session: PostJailbreakSession

    init(environment: PostJailbreakEnvironment) {
        self.environment = environment
        _session = StateObject(
            wrappedValue: PostJailbreakSession(environment: environment)
        )
    }

    var body: some View {
        NavigationStack {
            PostJailbreakHomeView(
                session: session,
                environment: environment
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .font(Theme.font)
        .dynamicTypeSize(.medium)
        .tint(Theme.accent)
        .frame(minWidth: minSize?.width, minHeight: minSize?.height)
    }

    private var minSize: CGSize? {
        UIDevice.current.userInterfaceIdiom == .pad
            ? CGSize(width: 560, height: 760)
            : nil
    }
}
