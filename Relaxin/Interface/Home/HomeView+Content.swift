import SwiftUI

struct HomeContent<Action: Hashable>: View {
    let terminalText: String
    let terminalAccessibleLinks: [TerminalPresenter.AccessibleLink]
    let terminalHeight: CGFloat
    let rendersTerminalBackgroundActively: Bool
    let showsMenu: Bool
    let menuItems: [OptionListItem<Action>]
    let preferredMenuAction: Action?
    let secondaryMenuActions: Set<Action>
    let shareItems: [Action: URL]
    let loadingMenuActions: Set<Action>
    let disabledMenuActions: Set<Action>
    let isVolumeButtonInputEnabled: Bool
    let allowsOpeningTerminalLinks: Bool
    let onTerminalColumnCountChange: (Int) -> Void
    let onSelectMenuItem: (Action) -> Void
    var onTerminalLongPress: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let minimumLayoutHeight = HomeContentLayout.minimumMenuLayoutHeight(
                terminalHeight: terminalHeight
            )
            let compact = showsMenu && geometry.size.height < minimumLayoutHeight
            let expandableHeight = max(
                0,
                (geometry.size.height - minimumLayoutHeight) / 2
            )

            if compact {
                compactContent
            } else {
                regularContent(expandableHeight: expandableHeight)
            }
        }
        .padding(Theme.pagePadding)
        .background {
            ZStack {
                Theme.background

                TerminalCharacterBackground(
                    rendersActively: rendersTerminalBackgroundActively
                )
                .opacity(0.05)
            }
            .ignoresSafeArea()
        }
    }

    private var compactContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SwiftUI.Color.clear
                        .frame(height: HomeContentLayout.compactTopSpacing)

                    terminal(fixedHeight: true)

                    menu { action in
                        proxy.scrollTo(action, anchor: .center)
                    }
                    .padding(.leading, -OptionListLayout.markerGutter)

                    SwiftUI.Color.clear
                        .frame(height: HomeContentLayout.compactBottomSpacing)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .id(menuItems.map(\.id))
        }
    }

    private func regularContent(expandableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsMenu {
                SwiftUI.Color.clear
                    .frame(height: HomeContentLayout.minimumTopSpacing + expandableHeight)
            } else {
                Spacer(minLength: HomeContentLayout.minimumTopSpacing)
            }

            terminal(fixedHeight: showsMenu)

            if showsMenu {
                ScrollViewReader { proxy in
                    ScrollView {
                        menu { action in
                            proxy.scrollTo(action, anchor: .center)
                        }
                    }
                    .frame(
                        height: HomeContentLayout.minimumMenuViewportHeight + expandableHeight,
                        alignment: .top
                    )
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .padding(.leading, -OptionListLayout.markerGutter)
                    .id(menuItems.map(\.id))
                }

                SwiftUI.Color.clear
                    .frame(height: HomeContentLayout.minimumBottomSpacing)
            } else {
                Spacer(minLength: HomeContentLayout.minimumBottomSpacing)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func terminal(fixedHeight: Bool) -> some View {
        TerminalPresenter(
            content: terminalText,
            accessibleLinks: terminalAccessibleLinks,
            allowsOpeningLinks: allowsOpeningTerminalLinks,
            onColumnCountChange: onTerminalColumnCountChange,
            onLongPress: onTerminalLongPress
        )
        .frame(
            maxWidth: .infinity,
            minHeight: terminalHeight,
            maxHeight: fixedHeight ? terminalHeight : .infinity,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
    }

    private func menu(
        onSelectionChange: @escaping (Action) -> Void
    ) -> some View {
        OptionList(
            entries: menuItems,
            preferredSelection: preferredMenuAction,
            secondaryActions: secondaryMenuActions,
            shareItems: shareItems,
            loadingActions: loadingMenuActions,
            disabledActions: disabledMenuActions,
            isVolumeButtonInputEnabled: isVolumeButtonInputEnabled,
            onSelectionChange: onSelectionChange,
            onSelect: onSelectMenuItem
        )
        .padding(.top, 36)
    }
}
