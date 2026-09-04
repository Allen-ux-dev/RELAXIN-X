extension EngineSession {
    struct Failure {
        let report: String
    }

    enum Phase {
        case idle
        case running
        case finished
        case failed(Failure)
    }
}
