import CryptoKit
import Foundation
import ImageIO

enum ClipboardContentKind: String, Codable, Equatable {
    case text
    case image
    case file

    var systemImage: String {
        switch self {
        case .text:
            "text.alignleft"
        case .image:
            "photo"
        case .file:
            "doc"
        }
    }

    var displayName: String {
        switch self {
        case .text:
            L10n.kindText
        case .image:
            L10n.kindImage
        case .file:
            L10n.kindFile
        }
    }
}

struct ClipboardPayload: Codable, Equatable {
    var type: String
    var data: Data
}

enum ClipboardRichTextFormat: String, Equatable {
    case html
    case rtf
    case rtfd
}

struct ClipboardRichTextPreviewData: Equatable {
    var type: String
    var data: Data
    var format: ClipboardRichTextFormat
}

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ClipboardContentKind
    var text: String
    private var inlineImageData: Data?
    var imageDataFileName: String?
    private var imageDataFilePath: String?
    private var imagePixelSize: CGSize?
    private var imageDataDigest: String?
    var filePaths: [String]
    var payloads: [ClipboardPayload]
    let createdAt: Date
    var lastCopiedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        kind: ClipboardContentKind = .text,
        imageData: Data? = nil,
        filePaths: [String] = [],
        payloads: [ClipboardPayload] = [],
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.inlineImageData = imageData
        self.imageDataFileName = nil
        self.imageDataFilePath = nil
        self.imagePixelSize = imageData.flatMap(Self.imagePixelSize(from:))
        self.imageDataDigest = imageData.map(Self.imageDigest(from:))
        self.filePaths = filePaths
        self.payloads = payloads
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.isPinned = isPinned
    }

    init(
        id: UUID = UUID(),
        imageData: Data,
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.init(
            id: id,
            text: "[Image]",
            kind: .image,
            imageData: imageData,
            filePaths: [],
            payloads: [],
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            isPinned: isPinned
        )
    }

    init(
        id: UUID = UUID(),
        filePaths: [String],
        kind: ClipboardContentKind = .file,
        imageData: Data? = nil,
        payloads: [ClipboardPayload] = [],
        createdAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.init(
            id: id,
            text: filePaths.joined(separator: "\n"),
            kind: kind,
            imageData: imageData,
            filePaths: filePaths,
            payloads: payloads,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            isPinned: isPinned
        )
    }

    var isText: Bool {
        kind == .text
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.text == rhs.text
            && lhs.inlineImageData == rhs.inlineImageData
            && lhs.imageDataFileName == rhs.imageDataFileName
            && lhs.imageDataFilePath == rhs.imageDataFilePath
            && lhs.imagePixelSize == rhs.imagePixelSize
            && lhs.imageDataDigest == rhs.imageDataDigest
            && lhs.filePaths == rhs.filePaths
            && lhs.payloads == rhs.payloads
            && lhs.createdAt == rhs.createdAt
            && lhs.lastCopiedAt == rhs.lastCopiedAt
            && lhs.isPinned == rhs.isPinned
    }

    var imageData: Data? {
        if let inlineImageData {
            return inlineImageData
        }

        guard let imageDataURL else {
            return nil
        }

        return try? Data(contentsOf: imageDataURL)
    }

    var hasInlineImageData: Bool {
        inlineImageData != nil
    }

    var hasImageData: Bool {
        inlineImageData != nil || imageDataURL != nil
    }

    var needsExternalImageMigration: Bool {
        kind == .image && filePaths.isEmpty && inlineImageData != nil
    }

    var imageDataSource: ImageDataSource {
        ImageDataSource(
            id: "\(id.uuidString)-\(imageDataFileName ?? "inline")-\(inlineImageData?.count ?? 0)",
            inlineData: inlineImageData,
            filePath: imageDataURL?.path
        )
    }

    var imageDataURL: URL? {
        if let imageDataFilePath {
            return URL(fileURLWithPath: imageDataFilePath)
        }

        guard let imageDataFileName else {
            return nil
        }

        return ClipboardImageFileStore.defaultDirectoryURL
            .appending(path: imageDataFileName)
    }

    var richTextPreviewData: ClipboardRichTextPreviewData? {
        let candidates: [(ClipboardRichTextFormat, [String])] = [
            (.html, [
                "public.html",
                "text/html",
                "apple html pasteboard type",
                "html format"
            ]),
            (.rtf, [
                "public.rtf",
                "text/rtf",
                "rich text format"
            ]),
            (.rtfd, [
                "com.apple.flat-rtfd",
                "public.rtfd",
                "com.apple.rtfd"
            ])
        ]

        for (format, typeNames) in candidates {
            if let payload = payloads.first(where: { payload in
                let normalizedType = payload.type.lowercased()
                return typeNames.contains(normalizedType)
            }) {
                return ClipboardRichTextPreviewData(
                    type: payload.type,
                    data: payload.data,
                    format: format
                )
            }
        }

        return nil
    }

    var displayTitle: String {
        switch kind {
        case .text:
            return text
        case .image:
            if let firstPath = filePaths.first {
                return fileTitle(for: firstPath, count: filePaths.count)
            }

            if let imageSizeText {
                return "\(L10n.kindImage) \(imageSizeText)"
            }

            return L10n.kindImage
        case .file:
            guard let firstPath = filePaths.first else {
                return L10n.kindFile
            }

            return fileTitle(for: firstPath, count: filePaths.count)
        }
    }

    var detailText: String {
        switch kind {
        case .text:
            return text
        case .image:
            if filePaths.isEmpty {
                return L10n.kindImage
            }

            return filePaths.joined(separator: "\n")
        case .file:
            return filePaths.joined(separator: "\n")
        }
    }

    var searchableText: String {
        ([displayTitle, detailText] + filePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
            .joined(separator: "\n")
    }

    func contentMatches(_ other: ClipboardItem) -> Bool {
        guard kind == other.kind else {
            return false
        }

        switch kind {
        case .text:
            return text == other.text
        case .image:
            guard filePaths == other.filePaths else {
                return false
            }

            if !filePaths.isEmpty {
                return true
            }

            if let imageDataDigest, let otherImageDataDigest = other.imageDataDigest {
                return imageDataDigest == otherImageDataDigest
            }

            if let inlineImageData, let otherInlineImageData = other.inlineImageData {
                return inlineImageData == otherInlineImageData
            }

            return false
        case .file:
            return filePaths == other.filePaths
        }
    }

    func mergingMetadata(from newerItem: ClipboardItem, lastCopiedAt: Date) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: newerItem.kind,
            text: newerItem.text,
            inlineImageData: newerItem.inlineImageData,
            imageDataFileName: newerItem.imageDataFileName,
            imageDataFilePath: newerItem.imageDataFilePath,
            imagePixelSize: newerItem.imagePixelSize,
            imageDataDigest: newerItem.imageDataDigest,
            filePaths: newerItem.filePaths,
            payloads: newerItem.payloads,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            isPinned: isPinned
        )
    }

    func replacingDates(createdAt: Date, lastCopiedAt: Date) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            text: text,
            inlineImageData: inlineImageData,
            imageDataFileName: imageDataFileName,
            imageDataFilePath: imageDataFilePath,
            imagePixelSize: imagePixelSize,
            imageDataDigest: imageDataDigest,
            filePaths: filePaths,
            payloads: payloads,
            createdAt: createdAt,
            lastCopiedAt: lastCopiedAt,
            isPinned: isPinned
        )
    }

    private func fileTitle(for path: String, count: Int) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard count > 1 else {
            return name
        }

        return L10n.commonFileItemsMore(name: name, count: count)
    }

    private var imageSizeText: String? {
        guard let imagePixelSize,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            return nil
        }

        return "\(Int(imagePixelSize.width.rounded()))×\(Int(imagePixelSize.height.rounded()))"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case imageData
        case imageDataFileName
        case imagePixelSize
        case imageDataDigest
        case filePaths
        case payloads
        case createdAt
        case lastCopiedAt
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(ClipboardContentKind.self, forKey: .kind) ?? .text
        text = try container.decode(String.self, forKey: .text)
        inlineImageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageDataFileName = try container.decodeIfPresent(String.self, forKey: .imageDataFileName)
        imageDataFilePath = nil
        imagePixelSize = try container.decodeIfPresent(CGSize.self, forKey: .imagePixelSize)
            ?? inlineImageData.flatMap(Self.imagePixelSize(from:))
        imageDataDigest = try container.decodeIfPresent(String.self, forKey: .imageDataDigest)
            ?? inlineImageData.map(Self.imageDigest(from:))
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        payloads = try container.decodeIfPresent([ClipboardPayload].self, forKey: .payloads) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastCopiedAt = try container.decode(Date.self, forKey: .lastCopiedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(inlineImageData, forKey: .imageData)
        try container.encodeIfPresent(imageDataFileName, forKey: .imageDataFileName)
        try container.encodeIfPresent(imagePixelSize, forKey: .imagePixelSize)
        try container.encodeIfPresent(imageDataDigest, forKey: .imageDataDigest)
        try container.encode(filePaths, forKey: .filePaths)
        try container.encode(payloads, forKey: .payloads)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastCopiedAt, forKey: .lastCopiedAt)
        try container.encode(isPinned, forKey: .isPinned)
    }

    func resolvingImageFileDirectory(_ directoryURL: URL) -> ClipboardItem {
        guard let imageDataFileName, inlineImageData == nil else {
            return self
        }

        let filePath = directoryURL.appending(path: imageDataFileName).path
        return replacingImageStorage(
            inlineImageData: nil,
            imageDataFileName: imageDataFileName,
            imageDataFilePath: filePath,
            imagePixelSize: imagePixelSize ?? Self.imagePixelSize(at: URL(fileURLWithPath: filePath))
        )
    }

    func replacingImageStorage(
        inlineImageData: Data?,
        imageDataFileName: String?,
        imageDataFilePath: String?,
        imagePixelSize: CGSize? = nil,
        imageDataDigest: String? = nil
    ) -> ClipboardItem {
        var item = self
        item.inlineImageData = inlineImageData
        item.imageDataFileName = imageDataFileName
        item.imageDataFilePath = imageDataFilePath
        item.imagePixelSize = imagePixelSize
            ?? item.imagePixelSize
            ?? inlineImageData.flatMap(Self.imagePixelSize(from:))
        if let imageDataDigest {
            item.imageDataDigest = imageDataDigest
        } else if let inlineImageData {
            item.imageDataDigest = Self.imageDigest(from: inlineImageData)
        } else if imageDataFileName == nil {
            item.imageDataDigest = nil
        }
        return item
    }

    private init(
        id: UUID,
        kind: ClipboardContentKind,
        text: String,
        inlineImageData: Data?,
        imageDataFileName: String?,
        imageDataFilePath: String?,
        imagePixelSize: CGSize?,
        imageDataDigest: String?,
        filePaths: [String],
        payloads: [ClipboardPayload],
        createdAt: Date,
        lastCopiedAt: Date,
        isPinned: Bool
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.inlineImageData = inlineImageData
        self.imageDataFileName = imageDataFileName
        self.imageDataFilePath = imageDataFilePath
        self.imagePixelSize = imagePixelSize ?? inlineImageData.flatMap(Self.imagePixelSize(from:))
        self.imageDataDigest = imageDataDigest ?? inlineImageData.map(Self.imageDigest(from:))
        self.filePaths = filePaths
        self.payloads = payloads
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.isPinned = isPinned
    }

    nonisolated static func imageDigest(from data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func imagePixelSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    nonisolated private static func imagePixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}

enum ClipboardImageFileStore {
    nonisolated static var defaultDirectoryURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appending(path: "ClipPixTran", directoryHint: .isDirectory)
            .appending(path: "ClipboardImages", directoryHint: .isDirectory)
    }
}
