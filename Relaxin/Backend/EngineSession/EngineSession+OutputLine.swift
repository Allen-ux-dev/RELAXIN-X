import RelaxinEngine

extension TerminalOutputLine.Status {
    init(_ engineStatus: RLXEngineTaskStatus) {
        switch engineStatus {
        case .running:
            self = .running
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        @unknown default:
            self = .info
        }
    }
}

extension TerminalOutputLine {
    static func task(
        _ update: RLXEngineTaskUpdate,
        details: [String] = []
    ) -> Self {
        Self(
            label: update.message,
            status: .init(update.status),
            taskIdentifier: Int(update.stage.rawValue),
            position: Int(update.position),
            count: Int(update.count),
            details: details
        )
    }
}
