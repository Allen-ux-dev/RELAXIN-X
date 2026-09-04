import Foundation

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

var defaultSelection = PackageManagerSelection(rawValue: nil)
require(!defaultSelection.isEmpty, "default selection must never be empty")
require(defaultSelection.contains(.sileo), "default selection must contain Sileo")

let zebraOnly = PackageManagerSelection(selected: [.zebra])
require(!zebraOnly.isEmpty, "Zebra-only selection must count as selected")
require(zebraOnly.contains(.zebra), "Zebra-only selection must preserve Zebra")
require(!zebraOnly.contains(.sileo), "Zebra-only selection must not force Sileo")

let normalizedEmpty = PackageManagerSelection(selected: [])
require(!normalizedEmpty.isEmpty, "empty constructor input must normalize to a valid selection")
require(normalizedEmpty.contains(.sileo), "empty constructor input must normalize to Sileo")

let didToggleLastManager = defaultSelection.toggle(.sileo)
require(!didToggleLastManager, "the last package manager must not be removable")
require(!defaultSelection.isEmpty, "failed last-manager toggle must preserve non-empty selection")

print("PackageManagerSelection tests passed")
