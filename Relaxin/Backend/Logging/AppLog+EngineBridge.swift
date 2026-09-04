import Foundation
import RelaxinEngine

private let engineOutputLock = NSLock()
private nonisolated(unsafe) var engineOutputHandler: (@Sendable (String) -> Void)?

extension AppLog {
    static func connectEngineLogging() {
        rlx_engine_set_log_handler(writeEngineLog)
    }

    static func setEngineOutputHandler(
        _ handler: (@Sendable (String) -> Void)?
    ) {
        engineOutputLock.lock()
        engineOutputHandler = handler
        engineOutputLock.unlock()
    }
}

private func writeEngineLog(
    _ level: Int32,
    _ category: UnsafePointer<CChar>?,
    _ message: UnsafePointer<CChar>?
) {
    AppLog.writeNativeLog(level, category, message)

    guard level >= RLX_ENGINE_LOG_INFO else { return }
    let text = message.map { String(cString: $0) } ?? ""
    engineOutputLock.lock()
    let outputHandler = engineOutputHandler
    engineOutputLock.unlock()
    outputHandler?(text)
}
