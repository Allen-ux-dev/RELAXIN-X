import Foundation

/// Immutable package-manager intent captured for one jailbreak run.
///
/// The plan intentionally carries only manager identities. Artifact paths and
/// other deployment details are resolved after the user confirms this value.
struct PackageManagerInstallPlan: Equatable, Sendable {
    let selected: Set<PackageManager>

    init(selected: Set<PackageManager>) {
        precondition(!selected.isEmpty, "a package-manager install plan must contain at least one manager")
        self.selected = selected
    }

    func contains(_ packageManager: PackageManager) -> Bool {
        selected.contains(packageManager)
    }
}
