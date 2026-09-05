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

let prismOnly = PackageManagerSelection(selected: [.prism])
require(prismOnly.contains(.prism), "Prism-only selection must preserve Prism")
require(prismOnly.encodedValue == "prism", "Prism-only selection must round-trip with stable raw value")

let allManagers = PackageManagerSelection(selected: [.sileo, .zebra, .prism])
require(allManagers.encodedValue == "sileo,zebra,prism", "all managers must encode in stable CaseIterable order")
let decodedAllManagers = PackageManagerSelection(rawValue: allManagers.encodedValue)
require(decodedAllManagers.contains(.sileo), "decoded all-manager selection must contain Sileo")
require(decodedAllManagers.contains(.zebra), "decoded all-manager selection must contain Zebra")
require(decodedAllManagers.contains(.prism), "decoded all-manager selection must contain Prism")

let legacySelection = PackageManagerSelection(rawValue: "sileo,zebra")
require(legacySelection.contains(.sileo) && legacySelection.contains(.zebra), "legacy Sileo+Zebra selection must remain compatible")
require(!legacySelection.contains(.prism), "legacy selection must not silently add Prism")

print("PackageManagerSelection tests passed")
