import Foundation

enum RelaxinTerminalContent {
    static func home(
        isJailbroken: Bool,
        packageManagerSummary: String? = nil,
        resourceBundle: Bundle
    ) -> String {
        var additionalReport: [(String, String)] = []
        if let packageManagerSummary {
            additionalReport.append(("packages", packageManagerSummary))
        }
        var lines = baseLines(
            isJailbroken: isJailbroken,
            additionalReport: additionalReport,
            resourceBundle: resourceBundle
        )
        lines.append("")
        lines.append(
            TerminalStyle.dim(
                String(
                    localized: "Tap options below to start...",
                    bundle: resourceBundle
                )
            ) + " "
        )
        lines.append("")
        return TerminalStyle.clearAndHome + TerminalStyle.hideCursor + lines.joined(separator: "\r\n")
    }

    static func running(
        output: [TerminalOutputLine],
        isJailbroken: Bool,
        terminalWidth: Int,
        resourceBundle: Bundle
    ) -> String {
        var lines = baseLines(
            isJailbroken: isJailbroken,
            resourceBundle: resourceBundle
        )
        lines.append("")
        lines.append(TerminalStyle.accent("❯") + " relaxin do")
        lines.append("")
        lines.append(contentsOf: output.flatMap {
            render($0, width: terminalWidth)
        })
        lines.append("")
        return TerminalStyle.clearAndHome + TerminalStyle.hideCursor + lines.joined(separator: "\r\n")
    }

    static func command(
        command: String,
        output: [TerminalOutputLine],
        isJailbroken: Bool,
        terminalWidth: Int,
        resourceBundle: Bundle
    ) -> String {
        var lines = baseLines(
            isJailbroken: isJailbroken,
            resourceBundle: resourceBundle
        )
        lines.append("")
        lines.append(TerminalStyle.accent(">") + " \(command)")
        if !output.isEmpty {
            lines.append("")
            lines.append(contentsOf: output.flatMap {
                render($0, width: terminalWidth)
            })
        }
        return TerminalStyle.clearAndHome
            + TerminalStyle.hideCursor
            + lines.joined(separator: "\r\n")
    }

    /// Credits omits the RELAXIN-X banner and command header.
    static func credits(
        visibleCharacterCount: Int,
        terminalWidth: Int,
        linksEnabled: Bool
    ) -> String {
        let cursorVisibility = visibleCharacterCount < RelaxinCredits.characterCount
            ? TerminalStyle.showCursor
            : TerminalStyle.hideCursor
        return TerminalStyle.clearAndHome
            + cursorVisibility
            + RelaxinCredits.terminalLines(
                visibleCharacterCount: visibleCharacterCount,
                terminalWidth: terminalWidth,
                linksEnabled: linksEnabled
            ).joined(separator: "\r\n")
    }

    static func unavailable(resourceBundle: Bundle) -> String {
        var lines = baseLines(
            isJailbroken: false,
            resourceBundle: resourceBundle
        )
        lines.append("")
        lines.append(
            TerminalStyle.danger(
                String(
                    localized: "RELAXIN-X Lite requires an active RootHide jailbreak.",
                    bundle: resourceBundle
                )
            )
        )
        lines.append("")
        return TerminalStyle.clearAndHome
            + TerminalStyle.hideCursor
            + lines.joined(separator: "\r\n")
    }
}
