import Foundation

struct TerminalOutputLine {
    private static let detailLimit = 3

    enum Status: String {
        case info
        case running
        case succeeded = "ok"
        case failed
    }

    let label: String
    let status: Status
    let taskIdentifier: Int?
    let position: Int?
    let count: Int?
    let details: [String]

    init(
        label: String,
        status: Status,
        taskIdentifier: Int? = nil,
        position: Int? = nil,
        count: Int? = nil,
        details: [String] = []
    ) {
        self.label = label
        self.status = status
        self.taskIdentifier = taskIdentifier
        self.position = position
        self.count = count
        self.details = details
    }

    func appendingDetails(from message: String) -> Self {
        var updatedDetails = details
        for line in message.components(separatedBy: .newlines) {
            let detail = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty, detail != updatedDetails.last else { continue }
            updatedDetails.append(detail)
        }
        if updatedDetails.count > Self.detailLimit {
            updatedDetails.removeFirst(updatedDetails.count - Self.detailLimit)
        }
        return Self(
            label: label,
            status: status,
            taskIdentifier: taskIdentifier,
            position: position,
            count: count,
            details: updatedDetails
        )
    }
}
