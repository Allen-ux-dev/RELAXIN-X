enum RelaxinInterfaceMode: CaseIterable {
    case full
    case lite
    case overlay

    var showsJailbreakInterface: Bool {
        self != .lite
    }

    var showsPostJailbreakInterface: Bool {
        self != .overlay
    }

    var allowsSileoReinstallation: Bool {
        self == .full
    }

    var allowsExternalNavigation: Bool {
        self != .overlay
    }

    var allowsFileExport: Bool {
        self == .full
    }

    var showsMaintenance: Bool {
        self != .lite
    }
}
