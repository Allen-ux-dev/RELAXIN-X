import Foundation

enum RuntimeApplicationStateVerifier {
    static func verify(
        expected: RuntimeApplicationState,
        actual: RuntimeApplicationState
    ) throws -> Bool {
        guard expected == actual else {
            throw RuntimeServiceError.stateMismatch
        }
        return true
    }
}
