import Foundation
import RelaxinPostJailbreak

extension AppLog {
    static func connectPostJailbreakLogging() {
        rlx_post_jailbreak_set_log_handler(writePostJailbreakLog)
    }
}

private func writePostJailbreakLog(
    _ level: Int32,
    _ category: UnsafePointer<CChar>?,
    _ message: UnsafePointer<CChar>?
) {
    AppLog.writeNativeLog(level, category, message)
}
