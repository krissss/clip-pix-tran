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
    private let imageDirectoryURL: URL

    init(
        fileURL: URL = FileClipboardHistoryPersistence.defaultFileURL,
        imageDirectoryURL: URL? = nil
    ) {
        self.fileURL = fileURL
        self.imageDirectoryURL = imageDirectoryURL ?? Self.defaultImageDirectoryURL(for: fileURL)
    }

    func loadSnapshot() throws -> ClipboardHistorySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        var snapshot = try decoder.decode(ClipboardHistorySnapshot.self, from: data)
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

    func saveSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
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

    private func persistedItem(for item: ClipboardItem) throws -> ClipboardItem {
        guard item.kind == .image,
              item.hasImageData,
              item.filePaths.isEmpty else {
            return item
        }

        let fileName = item.imageDataFileName ?? "\(item.id.uuidString).img"
        let destinationURL = imageDirectoryURL.appending(path: fileName)
        var digest: String?
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            guard let imageData = item.imageData else {
                return item
            }
            digest = ClipboardItem.imageDigest(from: imageData)
            try imageData.write(to: destinationURL, options: [.atomic])
        }

        return item.replacingImageStorage(
            inlineImageData: nil,
            imageDataFileName: fileName,
            imageDataFilePath: nil,
            imageDataDigest: digest
        )
    }

    private func persistedSnapshot(for snapshot: ClipboardHistorySnapshot) throws -> ClipboardHistorySnapshot {
        let migratedItems = try snapshot.items.map { item in
            try persistedItem(for: item)
        }
        try removeUnreferencedImageFiles(keeping: Set(migratedItems.compactMap(\.imageDataFileName)))

        return ClipboardHistorySnapshot(
            items: migratedItems,
            maximumNormalItems: snapshot.maximumNormalItems,
            persistsHistory: snapshot.persistsHistory
        )
    }

    private func writeSnapshot(_ snapshot: ClipboardHistorySnapshot) throws {
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

    static var defaultFileURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appending(path: "ClipPixTran", directoryHint: .isDirectory)
            .appending(path: "clipboard-history.json")
    }

    private static func defaultImageDirectoryURL(for fileURL: URL) -> URL {
        if fileURL == defaultFileURL {
            return ClipboardImageFileStore.defaultDirectoryURL
        }

        return fileURL
            .deletingLastPathComponent()
            .appending(path: "ClipboardImages", directoryHint: .isDirectory)
    }
}
