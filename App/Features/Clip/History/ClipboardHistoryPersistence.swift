import Foundation

struct ClipboardHistorySnapshot: Codable, Equatable {
    var items: [ClipboardItem]
    var maximumNormalItems: Int
    var persistsHistory: Bool
}

protocol ClipboardHistoryPersistence: Sendable {
    nonisolated func loadSnapshot() throws -> ClipboardHistorySnapshot?
    nonisolated func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws
    nonisolated func deleteSnapshot() throws
}

struct FileClipboardHistoryPersistence: ClipboardHistoryPersistence {
    private let fileURL: URL

    init(fileURL: URL = FileClipboardHistoryPersistence.defaultFileURL) {
        self.fileURL = fileURL
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(ClipboardHistorySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
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
            .appending(path: "clipboard-history.json")
    }
}
