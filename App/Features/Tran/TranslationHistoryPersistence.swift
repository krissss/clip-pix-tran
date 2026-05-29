import Foundation

struct TranslationHistorySnapshot: Codable, Equatable, Sendable {
    var items: [TranslationHistoryItem]
    var maximumItems: Int
    var persistsHistory: Bool
}

protocol TranslationHistoryPersistence: Sendable {
    nonisolated func loadSnapshot() throws -> TranslationHistorySnapshot?
    nonisolated func saveSnapshot(_ snapshot: TranslationHistorySnapshot) throws
    nonisolated func deleteSnapshot() throws
}

struct FileTranslationHistoryPersistence: TranslationHistoryPersistence {
    private let fileURL: URL

    init(fileURL: URL = FileTranslationHistoryPersistence.defaultFileURL) {
        self.fileURL = fileURL
    }

    func loadSnapshot() throws -> TranslationHistorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(TranslationHistorySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: TranslationHistorySnapshot) throws {
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
            .appending(path: "translation-history.json")
    }
}
