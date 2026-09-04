import Foundation

enum RelaxinCredits {
    private enum EntryStyle: Equatable {
        case section
        case person
        case spacer
    }

    private struct Entry {
        let name: String
        let destination: URL?
        let role: String
        let style: EntryStyle

        private var roleText: String {
            guard style == .person, !role.isEmpty else { return "" }
            return "(\(role))"
        }

        func characterCount() -> Int {
            name.count + roleText.count
        }

        static func section(_ name: String) -> Entry {
            Entry(name: name, destination: nil, role: "", style: .section)
        }

        static func person(
            _ name: String,
            destination: URL? = nil,
            role: String = ""
        ) -> Entry {
            Entry(name: name, destination: destination, role: role, style: .person)
        }

        static let spacer = Entry(name: "", destination: nil, role: "", style: .spacer)

        /// Applies terminal styling after truncation so SwiftTerm always receives complete ANSI sequences.
        func terminalLines(
            visibleCharacterCount: Int,
            roleColumn: Int,
            terminalWidth: Int,
            linksEnabled: Bool
        ) -> [String] {
            guard style != .spacer else { return [""] }

            let visibleNameCount = min(max(0, visibleCharacterCount), name.count)
            let visibleName = String(name.prefix(visibleNameCount))
            guard !visibleName.isEmpty else { return [] }

            switch style {
            case .section:
                return RelaxinCredits.wrap(visibleName, width: terminalWidth).map(TerminalStyle.bold)
            case .person:
                let nameLines = RelaxinCredits.wrap(visibleName, width: terminalWidth).map { chunk in
                    var styled = TerminalStyle.accent(chunk)
                    if linksEnabled, let destination {
                        styled = TerminalStyle.hyperlink(styled, destination: destination)
                    }
                    return styled
                }
                guard visibleNameCount == name.count, !roleText.isEmpty else {
                    return nameLines
                }

                let visibleRoleCount = min(
                    max(0, visibleCharacterCount - name.count),
                    roleText.count
                )
                guard visibleRoleCount > 0 else { return nameLines }
                let visibleRole = String(roleText.prefix(visibleRoleCount))

                let alignedSpacing = max(minimumRoleSpacing, roleColumn - name.count)
                let alignedWidth = name.count + alignedSpacing + roleText.count
                if nameLines.count == 1, alignedWidth <= terminalWidth {
                    return [
                        nameLines[0]
                            + String(repeating: " ", count: alignedSpacing)
                            + TerminalStyle.dim(visibleRole)
                    ]
                }

                let compactWidth = name.count + minimumRoleSpacing + roleText.count
                if nameLines.count == 1, compactWidth <= terminalWidth {
                    return [
                        nameLines[0]
                            + String(repeating: " ", count: minimumRoleSpacing)
                            + TerminalStyle.dim(visibleRole)
                    ]
                }

                let roleLines = RelaxinCredits.wrap(
                    visibleRole,
                    width: max(1, terminalWidth - minimumRoleSpacing)
                ).map {
                    TerminalStyle.dim(
                        String(repeating: " ", count: minimumRoleSpacing) + $0
                    )
                }
                return nameLines + roleLines
            case .spacer:
                return [""]
            }
        }
    }

    private static let title = "RELAXIN-X"
    private static let minimumRoleSpacing = 2

    private static let entries: [Entry] = [
        .spacer,
        .section("RELAXIN-X Maintainer"),
        .person(
            "Allen-ux-dev",
            destination: URL(string: "https://github.com/Allen-ux-dev")!,
            role: "Maintainer"
        ),
        .spacer,
        .section("Original Relaxin / Upstream"),
        .person(
            "@Lakr233",
            destination: URL(string: "https://x.com/Lakr233")!,
            role: "SPTM, GPU Magic, UI"
        ),
        .person(
            "@0x88FFA357",
            destination: URL(string: "https://x.com/0x88FFA357")!,
            role: "SPTM/PPL, CI"
        ),
        .person(
            "@82Flex",
            destination: URL(string: "https://x.com/82Flex")!,
            role: "RootHide, PPL/TXM"
        ),
        .person(
            "@roothideDev",
            destination: URL(string: "https://x.com/roothideDev")!,
            role: "RootHide, TXM"
        ),
        .person(
            "@pattern_F_",
            destination: URL(string: "https://x.com/pattern_F_")!,
            role: "Exploits"
        ),
        .spacer,
        .section("AI / Tooling"),
        .person(
            "GPT‑5.6",
            destination: URL(string: "https://openai.com/index/previewing-gpt-5-6-sol/")!
        ),
        .person(
            "Kimi-K3",
            destination: URL(string: "https://www.kimi.com/blog/kimi-k3")!
        ),
        .spacer,
        .section("Acknowledgements"),
        .person(
            "@opa334dev",
            destination: URL(string: "https://x.com/opa334dev")!,
            role: "Dopamine"
        ),
        .person(
            "@Fayezheng_",
            destination: URL(string: "https://x.com/Fayezheng_")!
        ),
        .person(
            "@AkiNazuki",
            destination: URL(string: "https://x.com/AkiNazuki")!
        ),
        .person(
            "@EEEEYHN",
            destination: URL(string: "https://x.com/EEEEYHN")!
        ),
        .person(
            "@huamidev",
            destination: URL(string: "https://x.com/huami_1214")!
        ),
    ]

    private static let roleColumn =
        (entries.filter { $0.style == .person }.map(\.name.count).max() ?? 0)
            + minimumRoleSpacing

    static let characterCount = title.count + entries.reduce(0) { count, entry in
        count + entry.characterCount()
    }

    static func accessibleLinks(linksEnabled: Bool) -> [TerminalPresenter.AccessibleLink] {
        guard linksEnabled else { return [] }
        return entries.compactMap { entry in
            guard entry.style == .person, let destination = entry.destination else {
                return nil
            }
            return TerminalPresenter.AccessibleLink(label: entry.name, destination: destination)
        }
    }

    static func lineCount(terminalWidth: Int) -> Int {
        terminalLines(
            visibleCharacterCount: characterCount,
            terminalWidth: terminalWidth,
            linksEnabled: false
        ).count
    }

    static func terminalLines(
        visibleCharacterCount: Int,
        terminalWidth: Int,
        linksEnabled: Bool
    ) -> [String] {
        let width = max(1, terminalWidth)
        var remainingCharacterCount = min(max(0, visibleCharacterCount), characterCount)
        guard remainingCharacterCount > 0 else { return [] }

        let visibleTitleCharacterCount = min(remainingCharacterCount, title.count)
        let visibleTitle = String(title.prefix(visibleTitleCharacterCount))
        var lines = wrap(visibleTitle, width: width).map(TerminalStyle.bold)
        remainingCharacterCount -= visibleTitleCharacterCount

        for entry in entries {
            let characterCount = entry.characterCount()
            if characterCount == 0 {
                guard remainingCharacterCount > 0 else { break }
                lines.append("")
                continue
            }

            guard remainingCharacterCount > 0 else { break }
            let entryCharacterCount = min(remainingCharacterCount, characterCount)
            lines.append(contentsOf: entry.terminalLines(
                visibleCharacterCount: entryCharacterCount,
                roleColumn: roleColumn,
                terminalWidth: width,
                linksEnabled: linksEnabled
            ))
            remainingCharacterCount -= entryCharacterCount
        }

        return lines
    }

    private static func wrap(_ text: String, width: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        let width = max(1, width)
        var remaining = text[...]
        var result: [String] = []

        while !remaining.isEmpty {
            let proposedEnd = remaining.index(
                remaining.startIndex,
                offsetBy: min(width, remaining.count)
            )
            var lineEnd = proposedEnd
            if proposedEnd != remaining.endIndex {
                let proposedLine = remaining[..<proposedEnd]
                if let space = proposedLine.lastIndex(of: " "),
                   space != remaining.startIndex
                {
                    lineEnd = space
                }
            }

            result.append(String(remaining[..<lineEnd]))
            remaining = remaining[lineEnd...]
            while remaining.first == " " {
                remaining = remaining.dropFirst()
            }
        }
        return result
    }
}
