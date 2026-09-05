import Foundation

/// Mutable UI draft used only while the final install confirmation is visible.
struct PackageManagerConfirmationDraft: Equatable {
    private(set) var selection: PackageManagerSelection

    init(selection: PackageManagerSelection) {
        self.selection = selection
    }

    @discardableResult
    mutating func toggle(_ packageManager: PackageManager) -> Bool {
        selection.toggle(packageManager)
    }

    func freeze() -> PackageManagerInstallPlan {
        PackageManagerInstallPlan(selected: selection.selected)
    }
}
