import AppKit
import ImageIO

private let fileThumbnailMaxPixels = 1024
private let maximumPasteboardImageBytes = 20 * 1024 * 1024
private let maximumFileImagePasteBytes = 200 * 1024 * 1024
private let maximumTextPayloadBytes = 20 * 1024 * 1024

struct SystemClipboardService: ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readItem() -> ClipboardItem? {
        if let fileItem = readFileItem() {
            return fileItem
        }

        if let imageData = readImageData() {
            return ClipboardItem(imageData: imageData)
        }

        guard let item = readTextItem() else {
            return nil
        }

        return item
    }

    func writeItem(_ item: ClipboardItem) throws {
        pasteboard.clearContents()

        let didWrite: Bool
        switch item.kind {
        case .text:
            didWrite = writeTextItem(item)
        case .image:
            didWrite = writeImageItem(item)
        case .file:
            didWrite = writeFileURLs(item.filePaths)
        }

        if !didWrite {
            throw ClipboardWriteError.rejected
        }
    }

    func readPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    func writePlainText(_ text: String) throws {
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
        if !didWrite {
            throw ClipboardWriteError.rejected
        }
    }

    private func readFileItem() -> ClipboardItem? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return nil
        }

        let paths = urls.map(\.path)
        let kind: ClipboardContentKind = pathsAreImages(paths) ? .image : .file
        let imageData = kind == .image && paths.count == 1
            ? Self.generateImageFileThumbnail(at: urls[0])
            : nil

        return ClipboardItem(
            filePaths: paths,
            kind: kind,
            imageData: imageData
        )
    }

    private func readTextItem() -> ClipboardItem? {
        guard let text = readPlainText() else {
            return nil
        }

        return ClipboardItem(
            text: text,
            payloads: readTextPayloads()
        )
    }

    private func readTextPayloads() -> [ClipboardPayload] {
        var payloads: [ClipboardPayload] = []
        var totalBytes = 0

        for type in pasteboard.types ?? [] {
            guard let data = pasteboard.data(forType: type),
                  !data.isEmpty else {
                continue
            }

            let nextTotalBytes = totalBytes + data.count
            guard nextTotalBytes <= maximumTextPayloadBytes else {
                continue
            }

            payloads.append(
                ClipboardPayload(
                    type: type.rawValue,
                    data: data
                )
            )
            totalBytes = nextTotalBytes
        }

        return payloads
    }

    private func readImageData() -> Data? {
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            .tiff
        ]

        for type in imageTypes {
            guard let data = pasteboard.data(forType: type) else {
                continue
            }

            guard data.count <= maximumPasteboardImageBytes else {
                return nil
            }

            return data
        }

        return nil
    }

    private func writeImageItem(_ item: ClipboardItem) -> Bool {
        let paths = item.filePaths
        if !paths.isEmpty {
            var writables: [NSPasteboardWriting] = paths.map { URL(fileURLWithPath: $0) as NSURL }
            if let data = imageDataForPaste(item),
               let image = NSImage(data: data) {
                writables.append(image)
            }

            guard !writables.isEmpty, pasteboard.writeObjects(writables) else {
                return false
            }

            setLegacyFilenames(paths)
            if let names = filenames(from: paths) {
                pasteboard.setString(names, forType: .string)
            }
            return true
        }

        guard let data = item.imageData else {
            return false
        }

        if let image = NSImage(data: data) {
            return pasteboard.writeObjects([image])
        }

        let didWritePNG = pasteboard.setData(data, forType: .png)
        let didWriteTIFF = pasteboard.setData(data, forType: .tiff)
        return didWritePNG || didWriteTIFF
    }

    private func writeTextItem(_ item: ClipboardItem) -> Bool {
        var didWritePayload = false

        for payload in item.payloads {
            let type = NSPasteboard.PasteboardType(payload.type)
            if pasteboard.setData(payload.data, forType: type) {
                didWritePayload = true
            }
        }

        let didWriteText = pasteboard.setString(item.text, forType: .string)
        return didWriteText || didWritePayload
    }

    private func writeFileURLs(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            return false
        }

        let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
        guard pasteboard.writeObjects(urls) else {
            return false
        }

        setLegacyFilenames(paths)
        if let names = filenames(from: paths) {
            pasteboard.setString(names, forType: .string)
        }
        return true
    }

    private func setLegacyFilenames(_ paths: [String]) {
        let pboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pasteboard.setPropertyList(paths, forType: pboardType)
    }

    private func imageDataForPaste(_ item: ClipboardItem) -> Data? {
        if let path = item.filePaths.first,
           let originalData = Self.loadOriginalImageData(at: path) {
            return originalData
        }

        return item.imageData
    }

    private func pathsAreImages(_ paths: [String]) -> Bool {
        guard !paths.isEmpty else {
            return false
        }

        return paths.allSatisfy { path in
            Self.imageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        }
    }

    private func filenames(from paths: [String]) -> String? {
        let names = paths
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            return nil
        }

        return names.joined(separator: "\n")
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "svg", "ico"
    ]

    private static func loadOriginalImageData(at path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maximumFileImagePasteBytes else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    private static func generateImageFileThumbnail(at fileURL: URL) -> Data? {
        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: fileThumbnailMaxPixels
            ]

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            }
        }

        guard let image = NSImage(contentsOf: fileURL),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        let maxPixel = CGFloat(fileThumbnailMaxPixels)
        let scale = min(maxPixel / image.size.width, maxPixel / image.size.height, 1)
        let pixelSize = NSSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        bitmap.size = pixelSize
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
