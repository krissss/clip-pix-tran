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
    var imageData: Data?
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
        self.imageData = imageData
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
            return filePaths == other.filePaths && imageData == other.imageData
        case .file:
            return filePaths == other.filePaths
        }
    }

    func mergingMetadata(from newerItem: ClipboardItem, lastCopiedAt: Date) -> ClipboardItem {
        ClipboardItem(
            id: id,
            text: newerItem.text,
            kind: newerItem.kind,
            imageData: newerItem.imageData,
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
            text: text,
            kind: kind,
            imageData: imageData,
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
        guard let imageData,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            return nil
        }

        return "\(width)×\(height)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case imageData
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
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
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
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(filePaths, forKey: .filePaths)
        try container.encode(payloads, forKey: .payloads)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastCopiedAt, forKey: .lastCopiedAt)
        try container.encode(isPinned, forKey: .isPinned)
    }
}
