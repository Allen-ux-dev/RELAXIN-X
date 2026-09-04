import Foundation

extension JailbreakConfiguration {
    enum JetsamMultiplier: String, CaseIterable, Hashable {
        case one = "1"
        case onePointFive = "1.5"
        case two = "2"
        case twoPointFive = "2.5"
        case three = "3"
        case threePointFive = "3.5"
        case four = "4"

        func title(in resourceBundle: Bundle) -> String {
            let multiplier = "\(rawValue)x"
            guard self == .three else { return multiplier }
            return "\(multiplier) (\(String(localized: "Recommended", bundle: resourceBundle)))"
        }
    }
}
