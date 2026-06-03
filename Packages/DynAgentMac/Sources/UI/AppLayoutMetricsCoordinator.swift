import Foundation

struct AppLayoutMetricsCoordinator {
    static let defaultFileName = "ui-layout-metrics.json"

    var directory: URL
    var fileName: String
    var fileManager: FileManager

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dynagent"),
        fileName: String = Self.defaultFileName,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileName = fileName
        self.fileManager = fileManager
    }

    func write(snapshot: WindowLayoutMetricsSnapshot) {
        write(payload: WindowLayoutModel.metricsPayload(from: snapshot))
    }

    func write(payload: [String: Any]) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: directory.appendingPathComponent(fileName))
    }
}
