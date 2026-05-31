import AppKit
import Foundation

enum SystemImagePreviewService {
    @MainActor
    static func openInPreviewApp(item: ClipboardItem) {
        guard let url = imageURL(for: item) else {
            return
        }

        openInPreviewApp(url: url)
    }

    @MainActor
    static func openInPreviewApp(item: ScreenshotItem) {
        guard let url = imageURL(for: item) else {
            return
        }

        openInPreviewApp(url: url)
    }

    @MainActor
    private static func openInPreviewApp(url: URL) {
        if let previewAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: previewAppURL, configuration: configuration) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func imageURL(for item: ScreenshotItem) -> URL? {
        writeTemporaryImageFile(data: item.data, id: item.id, prefix: "screenshot")
    }

    static func imageURL(for item: ClipboardItem) -> URL? {
        if let path = item.filePaths.first,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        guard let imageData = item.imageData else {
            return nil
        }

        return writeTemporaryImageFile(data: imageData, id: item.id)
    }

    static func canPreview(_ item: ClipboardItem) -> Bool {
        guard item.kind == .image else {
            return false
        }

        if let path = item.filePaths.first,
           FileManager.default.fileExists(atPath: path) {
            return true
        }

        return item.imageData != nil
    }

    static func imageFileExtension(from data: Data) -> String {
        let bytes = [UInt8](data.prefix(32))

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }

        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return "gif"
        }

        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "tiff"
        }

        if data.count >= 12 {
            let brandData = data[8..<min(data.count, 32)]
            if let brandText = String(data: brandData, encoding: .ascii),
               ["heic", "heix", "hevc", "hevx", "heim", "heis", "heif", "mif1", "msf1"].contains(where: brandText.contains) {
                return "heic"
            }
        }

        return "png"
    }

    private static func writeTemporaryImageFile(
        data: Data,
        id: UUID,
        prefix: String = "preview"
    ) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ClipPixTran-Preview",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("\(prefix)-\(id.uuidString).\(imageFileExtension(from: data))")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
