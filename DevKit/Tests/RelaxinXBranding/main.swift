import Foundation

enum TerminalPresenter {
    struct AccessibleLink: Equatable {
        let label: String
        let destination: URL
    }
}

let links = RelaxinCredits.accessibleLinks(linksEnabled: true)
precondition(links.first?.label == "Allen-ux-dev")
precondition(links.first?.destination.absoluteString == "https://github.com/Allen-ux-dev")
precondition(links.filter { $0.destination.absoluteString == "https://github.com/Allen-ux-dev" }.count == 1)

let rendered = RelaxinCredits.terminalLines(
    visibleCharacterCount: RelaxinCredits.characterCount,
    terminalWidth: 48,
    linksEnabled: false
).joined(separator: "\n")

precondition(rendered.contains("RELAXIN-X Maintainer"))
precondition(rendered.contains("Allen-ux-dev"))
precondition(rendered.contains("Original Relaxin / Upstream"))
precondition(
    rendered.range(of: "RELAXIN-X Maintainer")!.lowerBound
        < rendered.range(of: "Original Relaxin / Upstream")!.lowerBound
)
print("RELAXIN-X credits runtime contract: PASS")
