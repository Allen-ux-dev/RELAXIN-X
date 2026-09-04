import Foundation

enum AppLog {
    private static let lock = NSLock()

    /// Guarded by `lock`. Not main-actor-isolated so callers on any thread
    /// can log without hopping actors.
    private nonisolated(unsafe) static var configured = false

    static func bootstrap(dataDirectory: URL) {
        lock.lock()
        if configured {
            lock.unlock()
            AppLog.info(self, "bootstrap skipped already configured")
            return
        }
        let logsDirectory = dataDirectory.appendingPathComponent(
            "Logs",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try? Dog.shared.initialization(writableDir: logsDirectory)
        configured = true
        lock.unlock()
        AppLog.info(self, "bootstrap completed logsDir=\(logsDirectory.path)")
    }

    static func info(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .info)
    }

    static func error(_ kind: Any, _ message: String) {
        Dog.shared.join(categoryName(for: kind), message, level: .error)
    }

    static func categoryName(for kind: Any) -> String {
        if let string = kind as? String {
            return sanitizeCategoryName(string)
        }
        let typeName = if let type = kind as? Any.Type {
            String(describing: type)
        } else {
            String(describing: type(of: kind))
        }
        let name = typeName.split(separator: ".").last.map(String.init) ?? typeName
        return sanitizeCategoryName(name)
    }

    static func writeNativeLog(
        _ level: Int32,
        _ category: UnsafePointer<CChar>?,
        _ message: UnsafePointer<CChar>?
    ) {
        let dogLevel: Dog.DogLevel = switch level {
        case 0: .verbose
        case 1: .info
        case 2: .warning
        case 3: .error
        default: .critical
        }
        let categoryName = categoryName(
            for: category.map { String(cString: $0) } ?? "C"
        )
        let text = message.map { String(cString: $0) } ?? ""
        Dog.shared.join(categoryName, text, level: dogLevel)
    }

    private static func sanitizeCategoryName(_ name: String) -> String {
        guard !name.isEmpty else { return "Unknown" }
        var sanitized = name
        for ch: Character in ["[", "]", "|", "\n"] {
            sanitized = sanitized.filter { $0 != ch }
        }
        return sanitized.isEmpty ? "Unknown" : sanitized
    }
}
