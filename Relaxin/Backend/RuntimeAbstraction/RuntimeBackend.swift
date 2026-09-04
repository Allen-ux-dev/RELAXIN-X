import Foundation

protocol RuntimeBackend {
    var descriptor: RuntimeBackendDescriptor { get }

    func validate(environment: RuntimeEnvironment, profile: RuntimeProfile) -> Bool
}
