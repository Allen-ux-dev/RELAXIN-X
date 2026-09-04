import Foundation

enum RuntimeBackendRegistry {
    static let production: [RuntimeBackendDescriptor] = [
        LegacyRelaxinRuntimeBackend().descriptor,
    ]

    static func descriptor(id: String) -> RuntimeBackendDescriptor? {
        production.first { $0.id == id }
    }
}
