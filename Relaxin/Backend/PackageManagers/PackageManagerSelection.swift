import Foundation

enum PackageManager: String, CaseIterable, Hashable, Sendable {
    case sileo
    case zebra
    case prism

    var displayName: String {
        switch self {
        case .sileo: "Sileo"
        case .zebra: "Zebra"
        case .prism: "Prism"
        }
    }
}

struct PackageManagerSelection: Equatable {
    private(set) var selected: Set<PackageManager>

    init(rawValue: String?) {
        let decoded = Set(
            (rawValue ?? "")
                .split(separator: ",")
                .compactMap { PackageManager(rawValue: String($0)) }
        )
        selected = decoded.isEmpty ? [.sileo] : decoded
    }

    init(selected: Set<PackageManager>) {
        self.selected = selected.isEmpty ? [.sileo] : selected
    }

    var isEmpty: Bool {
        selected.isEmpty
    }

    var encodedValue: String {
        PackageManager.allCases
            .filter(selected.contains)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    func contains(_ packageManager: PackageManager) -> Bool {
        selected.contains(packageManager)
    }

    @discardableResult
    mutating func toggle(_ packageManager: PackageManager) -> Bool {
        if selected.contains(packageManager) {
            guard selected.count > 1 else { return false }
            selected.remove(packageManager)
        } else {
            selected.insert(packageManager)
        }
        return true
    }
}
