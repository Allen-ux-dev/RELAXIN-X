import Foundation

@inline(__always)
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

var persisted = PackageManagerSelection(selected: [.sileo, .prism])
var draft = PackageManagerConfirmationDraft(selection: persisted)
require(draft.selection.contains(.sileo), "draft inherits Sileo")
require(draft.selection.contains(.prism), "draft inherits Prism")
require(!draft.selection.contains(.zebra), "draft does not invent Zebra")

require(draft.toggle(.zebra), "draft can add Zebra")
let frozen = draft.freeze()
require(frozen.contains(.sileo), "frozen plan contains Sileo")
require(frozen.contains(.zebra), "frozen plan contains Zebra")
require(frozen.contains(.prism), "frozen plan contains Prism")

require(draft.toggle(.prism), "draft can change after freezing")
require(!draft.selection.contains(.prism), "draft mutation applies to draft")
require(frozen.contains(.prism), "frozen plan remains immutable")

var onlyPrism = PackageManagerConfirmationDraft(
    selection: PackageManagerSelection(selected: [.prism])
)
require(!onlyPrism.toggle(.prism), "confirmation cannot remove final manager")
require(onlyPrism.selection.contains(.prism), "failed toggle preserves final manager")

persisted.toggle(.prism)
require(draft.selection.contains(.sileo), "draft owns a value snapshot of persisted selection")

print("PackageManagerConfirmation tests passed")
