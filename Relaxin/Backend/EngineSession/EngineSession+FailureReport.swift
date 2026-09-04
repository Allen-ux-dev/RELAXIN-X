import Foundation
import RelaxinEngine

extension EngineSession {
    func makeFailureReport(for error: NSError) -> String {
        let reason = error.localizedFailureReason
            ?? String(
                localized: "No failure reason was provided.",
                bundle: runtime.resourceBundle
            )
        let recovery = error.localizedRecoverySuggestion
            ?? String(
                localized: "No recovery suggestion was provided.",
                bundle: runtime.resourceBundle
            )
        let diagnostic = error.userInfo[RLXEngineErrorUserInfoKey.diagnosticKey.rawValue] as? String
            ?? String(
                localized: "No engine diagnostics were provided.",
                bundle: runtime.resourceBundle
            )
        let eventLog: String
        if let line = output.last(where: { $0.status == .failed }) {
            var header = ""
            if let position = line.position, let count = line.count {
                header = "[\(position)/\(count)] "
            }
            header += "\(line.label) [\(line.status.rawValue)]"
            var lines = [header]
            if let detail = line.details.last {
                lines.append("  \(detail)")
            }
            eventLog = lines.joined(separator: "\n")
        } else {
            eventLog = String(
                localized: "No failed stage output was captured.",
                bundle: runtime.resourceBundle
            )
        }

        return """
        RELAXIN FAILURE REPORT
        ======================
        STOP CODE    RLX_ENGINE_\(error.code)
        DOMAIN       \(error.domain)
        MESSAGE      \(error.localizedDescription)
        REASON       \(reason)
        RECOVERY     \(recovery)

        DEVICE
        app          \(AppInfo.version(in: runtime.resourceBundle)) (\(AppInfo.build(in: runtime.resourceBundle))
        architecture \(AppInfo.arch)
        os           \(DeviceInfo.os)
        host         \(DeviceInfo.host)

        ENGINE LOG
        \(eventLog)

        DIAGNOSTICS
        \(diagnostic)
        """
    }
}
