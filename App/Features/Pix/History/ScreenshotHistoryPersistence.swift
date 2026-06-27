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
    private let imageDirectoryURL: URL

    init(
        fileURL: URL = FileScreenshotHistoryPersistence.defaultFileURL,
        imageDirectoryURL: URL? = nil
    ) {
        self.fileURL = fileURL
        self.imageDirectoryURL = imageDirectoryURL ?? Self.defaultImageDirectoryURL(for: fileURL)
    }

    func loadSnapshot() throws -> ScreenshotHistorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        var snapshot = try decoder.decode(ScreenshotHistorySnapshot.self, from: data)
        if snapshot.items.contains(where: \.needsExternalImageMigration) {
            try ensureStorageDirectories()
            snapshot = try persistedSnapshot(for: snapshot)
            try writeSnapshot(snapshot)
        }
        snapshot.items = snapshot.items.map {
            $0.resolvingImageFileDirectory(imageDirectoryURL)
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: ScreenshotHistorySnapshot) throws {
        try ensureStorageDirectories()

        try writeSnapshot(try persistedSnapshot(for: snapshot))
    }

    func deleteSnapshot() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        if FileManager.default.fileExists(atPath: imageDirectoryURL.path) {
            try FileManager.default.removeItem(at: imageDirectoryURL)
        }

    }

    private func persistedItem(for item: ScreenshotItem) throws -> ScreenshotItem {
        guard item.isImage, item.hasImageData else {
            return item
        }

        let fileName = item.dataFileName ?? "\(item.id.uuidString).png"
        let destinationURL = imageDirectoryURL.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            let data = item.data
            guard !data.isEmpty else {
                return item
            }
            try data.write(to: destinationURL, options: [.atomic])
        }

        let fileSize = fileSize(at: destinationURL) ?? item.byteCount
        return item.replacingImageStorage(
            inlineData: nil,
            dataFileName: fileName,
            dataFilePath: nil,
            fileSize: fileSize
        )
    }

    private func persistedSnapshot(for snapshot: ScreenshotHistorySnapshot) throws -> ScreenshotHistorySnapshot {
        let migratedItems = try snapshot.items.map { item in
            try persistedItem(for: item)
        }
        try removeUnreferencedImageFiles(keeping: Set(migratedItems.compactMap(\.dataFileName)))

        return ScreenshotHistorySnapshot(
            items: migratedItems,
            maximumItems: snapshot.maximumItems,
            persistsHistory: snapshot.persistsHistory
        )
    }

    private func writeSnapshot(_ snapshot: ScreenshotHistorySnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureStorageDirectories() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: imageDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func removeUnreferencedImageFiles(keeping fileNames: Set<String>) throws {
        guard FileManager.default.fileExists(atPath: imageDirectoryURL.path) else {
            return
        }

        let storedFileURLs = try FileManager.default.contentsOfDirectory(
            at: imageDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for fileURL in storedFileURLs where !fileNames.contains(fileURL.lastPathComponent) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
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

    private static func defaultImageDirectoryURL(for fileURL: URL) -> URL {
        if fileURL == defaultFileURL {
            return ScreenshotImageFileStore.defaultDirectoryURL
        }

        return fileURL
            .deletingLastPathComponent()
            .appending(path: "ScreenshotImages", directoryHint: .isDirectory)
    }
}
