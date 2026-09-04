import Foundation

extension AppLog {
    private static let exportArchivePrefix = "RELAXIN-X-Logs-"

    static func makeExportArchive(
        in temporaryDirectory: URL,
        supplementalFiles: [URL] = []
    ) async throws -> URL {
        AppLog.info(self, "log export started")
        let fileManager = FileManager.default
        let files = Dog.shared.obtainAllLogFilePath()
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let timestamp = Int(Date().timeIntervalSince1970)
        let destination = temporaryDirectory
            .appendingPathComponent("\(exportArchivePrefix)\(timestamp).zip")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        let exportFiles = (files + supplementalFiles)
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        do {
            try await writeExportArchive(files: exportFiles, destination: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        AppLog.info(self, "log export completed files=\(exportFiles.count)")
        return destination
    }

    @concurrent
    private static func writeExportArchive(files: [URL], destination: URL) async throws {
        let archive = try Archive(url: destination, accessMode: .create)
        for file in files {
            try Task.checkCancellation()
            try archive.addEntry(with: file.lastPathComponent, fileURL: file)
        }
    }

    static func removeStaleExportArchives(in temporaryDirectory: URL) {
        let fileManager = FileManager.default
        let temporaryItems: [URL]
        do {
            temporaryItems = try fileManager.contentsOfDirectory(
                at: temporaryDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            AppLog.error(self, "log export cleanup failed: \(error.localizedDescription)")
            return
        }

        for item in temporaryItems
            where item.lastPathComponent.hasPrefix(exportArchivePrefix)
            && item.pathExtension == "zip"
        {
            do {
                try fileManager.removeItem(at: item)
            } catch {
                AppLog.error(
                    self,
                    "log export cleanup failed file=\(item.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
    }
}
