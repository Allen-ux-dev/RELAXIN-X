import Foundation

enum TerminalPresenter {
    struct AccessibleLink: Equatable {
        let label: String
        let destination: URL
    }
}

private func stripANSI(_ value: String) -> String {
    value.replacingOccurrences(
        of: "\\u001B\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}

let fullCount = RelaxinCredits.characterCount
let wideLines = RelaxinCredits.terminalLines(
    visibleCharacterCount: fullCount,
    terminalWidth: 48,
    linksEnabled: false
).map(stripANSI)
let narrowLines = RelaxinCredits.terminalLines(
    visibleCharacterCount: fullCount,
    terminalWidth: 28,
    linksEnabled: false
).map(stripANSI)

precondition(wideLines.contains { $0.contains("@Lakr233") && $0.contains("(SPTM, GPU Magic, UI)") })

let lakrIndex = narrowLines.firstIndex(of: "@Lakr233")
precondition(lakrIndex != nil)
if let lakrIndex {
    precondition(narrowLines.indices.contains(lakrIndex + 1))
    precondition(narrowLines[lakrIndex + 1].trimmingCharacters(in: .whitespaces) == "(SPTM, GPU Magic, UI)")
}

precondition(RelaxinCredits.lineCount(terminalWidth: 28) == narrowLines.count)
precondition(RelaxinCredits.lineCount(terminalWidth: 48) == wideLines.count)
precondition(RelaxinCredits.lineCount(terminalWidth: 28) > RelaxinCredits.lineCount(terminalWidth: 48))

print("PASS Fix13.7 credits responsive layout")
