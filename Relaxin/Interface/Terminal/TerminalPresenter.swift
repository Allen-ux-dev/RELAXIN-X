import Foundation
import SwiftUI

/// Read-only SwiftTerm surface used for banners and engine output. It never
/// scrolls, accepts keyboard focus, or allows text selection.
struct TerminalPresenter: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let content: String
    let accessibleLinks: [AccessibleLink]
    let allowsOpeningLinks: Bool
    let onColumnCountChange: (Int) -> Void
    var onLongPress: (() -> Void)?

    func makeUIView(context _: Context) -> ReadOnlyView {
        let view = ReadOnlyView(frame: .zero, font: TerminalStyle.presenterFont)
        view.onColumnCountChange = onColumnCountChange
        view.onOpenLink = allowsOpeningLinks ? { [openURL] in openURL($0) } : nil
        view.onLongPress = onLongPress
        view.accessibleLinks = allowsOpeningLinks ? accessibleLinks : []
        view.isScrollEnabled = false
        // Read-only surfaces never gain focus, so cursor rendering must remain independent of responder state.
        view.caretViewTracksFocus = false
        TerminalStyle.configure(view, colorScheme: colorScheme)
        view.render(content)
        return view
    }

    func updateUIView(_ view: ReadOnlyView, context _: Context) {
        view.onColumnCountChange = onColumnCountChange
        view.onOpenLink = allowsOpeningLinks ? { [openURL] in openURL($0) } : nil
        view.onLongPress = onLongPress
        view.accessibleLinks = allowsOpeningLinks ? accessibleLinks : []
        TerminalStyle.applyColors(to: view, colorScheme: colorScheme)
        view.render(content)
    }
}

extension TerminalPresenter {
    struct AccessibleLink: Equatable {
        let label: String
        let destination: URL
    }

    final class ReadOnlyView: TerminalView {
        var onColumnCountChange: ((Int) -> Void)?
        var onOpenLink: ((URL) -> Void)?
        var onLongPress: (() -> Void)?
        var accessibleLinks: [AccessibleLink] = [] {
            didSet {
                guard accessibleLinks != oldValue else { return }
                accessibilityCustomActions = accessibleLinks.map { link in
                    UIAccessibilityCustomAction(name: link.label) { [weak self] _ in
                        guard let self else { return false }
                        onOpenLink?(link.destination)
                        return true
                    }
                }
            }
        }

        private var renderedContent: String?
        private var reportedColumnCount: Int?

        override var canBecomeFirstResponder: Bool {
            false
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let columnCount = getTerminal().cols
            guard columnCount != reportedColumnCount else { return }
            reportedColumnCount = columnCount
            DispatchQueue.main.async { [weak self] in
                guard self?.reportedColumnCount == columnCount else { return }
                self?.onColumnCountChange?(columnCount)
            }
        }

        override func canPerformAction(_: Selector, withSender _: Any?) -> Bool {
            false
        }

        override func singleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended else { return }
            let position = calculateTapHit(gesture: gestureRecognizer).grid
            guard let link = getTerminal().link(
                at: .buffer(position),
                mode: .explicitOnly
            ) else {
                return
            }
            guard let destination = URL(string: link) else {
                preconditionFailure("Invalid terminal hyperlink: \(link)")
            }
            onOpenLink?(destination)
        }

        override func copy(_: Any?) {}

        override func select(_: Any?) {}

        override func selectAll(_: Any?) {}

        override func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
            guard gestureRecognizer.state == .began else { return }
            onLongPress?()
        }

        override func doubleTap(_: UITapGestureRecognizer) {}

        override func tripleTap(_: UITapGestureRecognizer) {}

        override func showContextMenu(forRegion _: CGRect, pos _: Position) {}

        func render(_ content: String) {
            guard content != renderedContent else { return }
            renderedContent = content
            feed(text: content)
            selection.selectNone()
            disableSelectionPanGesture()
        }
    }
}
