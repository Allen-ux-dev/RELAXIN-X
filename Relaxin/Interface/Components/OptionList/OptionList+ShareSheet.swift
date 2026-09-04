import SwiftUI
import UIKit

extension OptionList {
    struct SharePresentation: Identifiable {
        let url: URL

        var id: URL {
            url
        }
    }

    struct ShareSheet: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context _: Context) -> UIActivityViewController {
            UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
        }

        func updateUIViewController(
            _: UIActivityViewController,
            context _: Context
        ) {}
    }
}
