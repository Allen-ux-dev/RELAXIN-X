import Foundation

extension PostJailbreakHomeView {
    struct Alert: Identifiable {
        enum Kind {
            case notice
            case userspaceRebootRequired
        }

        let title: String
        let message: String
        var kind = Kind.notice

        var id: String {
            "\(kind)\0\(title)\0\(message)"
        }

        static func userspaceRebootRequired(
            in resourceBundle: Bundle
        ) -> Alert {
            Alert(
                title: String(
                    localized: "Userspace Reboot Required",
                    bundle: resourceBundle
                ),
                message: String(
                    localized: "A userspace reboot is necessary to apply the changes. Do you want to do it now?",
                    bundle: resourceBundle
                ),
                kind: .userspaceRebootRequired
            )
        }
    }
}
