import Foundation

struct OptionListItem<Action: Hashable>: Identifiable {
    let id: Action
    let title: String
}
