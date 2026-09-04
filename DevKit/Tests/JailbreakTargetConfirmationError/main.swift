import Foundation

let error = JailbreakTarget.ConfirmationError.unsupportedSoC(0xDEADBEEF)
let description = error.localizedDescription(in: .main)
if !description.contains("0xDEADBEEF") {
    fputs("FAIL: unsupportedSoC description did not include formatted CPU family: \(description)\n", stderr)
    exit(1)
}
print("PASS JailbreakTargetConfirmationError executable")
