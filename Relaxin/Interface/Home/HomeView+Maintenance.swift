import Foundation

extension HomeView {
    enum LogExportState: Equatable {
        case idle
        case preparing(UUID)
        case ready(URL)

        var archiveURL: URL? {
            guard case let .ready(url) = self else { return nil }
            return url
        }

        var isPreparing: Bool {
            guard case .preparing = self else { return false }
            return true
        }
    }

    var softwareLicenseURL: URL? {
        runtime.resourceBundle.url(forResource: "Licenses", withExtension: "txt")
    }

    var kernelcacheExportURL: URL? {
        let stagedKernelcacheURL = runtime.dataDirectory.appendingPathComponent(
            "kernelcache",
            isDirectory: false
        )
        return FileManager.default.isReadableFile(atPath: stagedKernelcacheURL.path)
            ? stagedKernelcacheURL
            : nil
    }

    func prepareLogExport() {
        guard runtime.interfaceMode.allowsFileExport,
              !logExportState.isPreparing
        else {
            return
        }

        let request = UUID()
        logExportState = .preparing(request)
        Task {
            var diagnosticURL: URL?
            var diagnosticDirectoryURL: URL?
            defer {
                if let diagnosticURL {
                    try? FileManager.default.removeItem(at: diagnosticURL)
                }
                if let diagnosticDirectoryURL {
                    try? FileManager.default.removeItem(at: diagnosticDirectoryURL)
                }
            }

            do {
                var supplementalFiles: [URL] = []
                if let diagnosticJSON = engineSession.environmentDiagnosticJSON(),
                   let diagnosticData = diagnosticJSON.data(using: .utf8)
                {
                    let directory = runtime.temporaryDirectory.appendingPathComponent(
                        "RELAXIN-X-Diagnostics-\(UUID().uuidString)",
                        isDirectory: true
                    )
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    diagnosticDirectoryURL = directory
                    let file = directory.appendingPathComponent(
                        "environment-diagnostics.json",
                        isDirectory: false
                    )
                    try diagnosticData.write(to: file, options: [.atomic])
                    diagnosticURL = file
                    supplementalFiles.append(file)
                }

                let url = try await AppLog.makeExportArchive(
                    in: runtime.temporaryDirectory,
                    supplementalFiles: supplementalFiles
                )
                guard logExportState == .preparing(request) else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                logExportState = .ready(url)
            } catch {
                guard logExportState == .preparing(request) else { return }
                logExportState = .idle
                AppLog.error(Self.self, "log export failed: \(error.localizedDescription)")
                alert = Presentation.Alert(
                    title: String(
                        localized: "Export Failed",
                        bundle: runtime.resourceBundle
                    ),
                    message: error.localizedDescription
                )
            }
        }
    }

    func showSoftwareLicenseUnavailable() {
        guard runtime.interfaceMode.allowsExternalNavigation else { return }
        let message = String(
            localized: "The software license file is missing.",
            bundle: runtime.resourceBundle
        )
        AppLog.error(Self.self, message)
        alert = Presentation.Alert(
            title: String(
                localized: "Software License Unavailable",
                bundle: runtime.resourceBundle
            ),
            message: message
        )
    }

    func showKernelcacheUnavailable() {
        guard runtime.interfaceMode.allowsFileExport else { return }
        let message = String(
            localized: "The kernelcache is not readable.",
            bundle: runtime.resourceBundle
        )
        AppLog.error(Self.self, message)
        alert = Presentation.Alert(
            title: String(
                localized: "Export Failed",
                bundle: runtime.resourceBundle
            ),
            message: message
        )
    }

    func resetRelaxin() {
        logExportState = .idle
        do {
            try RelaxinReset.perform(runtime: runtime)
            configuration = JailbreakConfiguration(defaults: runtime.defaults)
            engineSession.reset()
            screen = .home
            alert = Presentation.Alert(
                title: String(
                    localized: "RELAXIN-X Reset",
                    bundle: runtime.resourceBundle
                ),
                message: String(
                    localized: "RELAXIN-X settings and caches were cleared.",
                    bundle: runtime.resourceBundle
                )
            )
        } catch {
            AppLog.error(Self.self, "reset failed: \(error.localizedDescription)")
            alert = Presentation.Alert(
                title: String(
                    localized: "Reset Failed",
                    bundle: runtime.resourceBundle
                ),
                message: error.localizedDescription
            )
        }
    }
}
