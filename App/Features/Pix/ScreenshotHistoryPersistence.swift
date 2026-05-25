import Foundation

struct ScreenshotHistorySnapshot: Codable, Equatable {
    var items: [ScreenshotItem]
    var maximumItems: Int
    var persistsHistory: Bool
}

protocol ScreenshotHistoryPersistence: Sendable {
    nonisolated func loadSnapshot() throws -> ScreenshotHistorySnapshot?
    nonisolated func saveSnapshot(_ snapshot: ScreenshotHistorySnapshot) throws
    nonisolated func deleteSnapshot() throws
}

struct FileScreenshotHistoryPersistence: ScreenshotHistoryPersistence {
    private let fileURL: URL

    init(fileURL: URL = FileScreenshotHistoryPersistence.defaultFileURL) {
        self.fileURL = fileURL
    }

    func loadSnapshot() throws -> ScreenshotHistorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(ScreenshotHistorySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ScreenshotHistorySnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func deleteSnapshot() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    static var defaultFileURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appending(path: "ClipPixTran", directoryHint: .isDirectory)
            .appending(path: "screenshot-history.json")
    }
}
