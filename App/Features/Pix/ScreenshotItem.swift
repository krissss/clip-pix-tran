import CoreGraphics
import Foundation
import ImageIO

struct ScreenshotItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case image
        case recording
    }

    enum CaptureSource: String, Codable {
        case selectedRegion
        case fullScreen
    }

    let id: UUID
    let kind: Kind
    private let inlineData: Data?
    let dataFileName: String?
    private let dataFilePath: String?
    let createdAt: Date
    let captureSource: CaptureSource?
    let recordingFileName: String?
    let duration: TimeInterval?
    let pixelSize: CGSize?
    let fileSize: Int64?
    /// OCR 识别出的文字。nil 表示未识别过；空字符串表示已识别但无文字。
    var recognizedText: String?

    init(
        id: UUID = UUID(),
        data: Data,
        createdAt: Date = Date(),
        captureSource: CaptureSource = .selectedRegion
    ) {
        self.id = id
        self.kind = .image
        self.inlineData = data
        self.dataFileName = nil
        self.dataFilePath = nil
        self.createdAt = createdAt
        self.captureSource = captureSource
        self.recordingFileName = nil
        self.duration = nil
        self.pixelSize = Self.imagePixelSize(from: data)
        self.fileSize = Int64(data.count)
        self.recognizedText = nil
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.inlineData == rhs.inlineData
            && lhs.dataFileName == rhs.dataFileName
            && lhs.dataFilePath == rhs.dataFilePath
            && lhs.createdAt == rhs.createdAt
            && lhs.captureSource == rhs.captureSource
            && lhs.recordingFileName == rhs.recordingFileName
            && lhs.duration == rhs.duration
            && lhs.pixelSize == rhs.pixelSize
            && lhs.fileSize == rhs.fileSize
            && lhs.recognizedText == rhs.recognizedText
    }

    init(
        id: UUID = UUID(),
        recordingFileName: String,
        createdAt: Date = Date(),
        duration: TimeInterval,
        pixelSize: CGSize,
        fileSize: Int64?
    ) {
        self.id = id
        self.kind = .recording
        self.inlineData = nil
        self.dataFileName = nil
        self.dataFilePath = nil
        self.createdAt = createdAt
        self.captureSource = nil
        self.recordingFileName = recordingFileName
        self.duration = duration
        self.pixelSize = pixelSize
        self.fileSize = fileSize
        self.recognizedText = nil
    }

    var isImage: Bool {
        kind == .image
    }

    var isRecording: Bool {
        kind == .recording
    }

    var data: Data {
        guard isImage else {
            return Data()
        }

        if let inlineData {
            return inlineData
        }

        guard let imageDataURL else {
            return Data()
        }

        return (try? Data(contentsOf: imageDataURL)) ?? Data()
    }

    var hasInlineData: Bool {
        inlineData != nil
    }

    var hasImageData: Bool {
        inlineData != nil || imageDataURL != nil
    }

    var needsExternalImageMigration: Bool {
        isImage && inlineData != nil
    }

    var recordingURL: URL? {
        guard let recordingFileName else {
            return nil
        }

        return ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: recordingFileName)
    }

    var imageDataSource: ImageDataSource {
        let sourceByteCount = inlineData.map { Int64($0.count) } ?? fileSize ?? 0

        return ImageDataSource(
            id: "\(id.uuidString)-\(dataFileName ?? "inline")-\(sourceByteCount)",
            inlineData: inlineData,
            filePath: imageDataURL?.path
        )
    }

    var imageDataURL: URL? {
        if let dataFilePath {
            return URL(fileURLWithPath: dataFilePath)
        }

        guard let dataFileName else {
            return nil
        }

        return ScreenshotImageFileStore.defaultDirectoryURL
            .appending(path: dataFileName)
    }

    var byteCount: Int64 {
        switch kind {
        case .image:
            if let fileSize {
                return fileSize
            }

            guard let imageDataURL,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: imageDataURL.path),
                  let size = attributes[.size] as? NSNumber else {
                return Int64(inlineData?.count ?? 0)
            }

            return size.int64Value
        case .recording:
            if let fileSize {
                return fileSize
            }

            guard let recordingURL,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: recordingURL.path),
                  let size = attributes[.size] as? NSNumber else {
                return 0
            }

            return size.int64Value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case data
        case dataFileName
        case createdAt
        case captureSource
        case recordingFileName
        case duration
        case pixelSize
        case fileSize
        case recognizedText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .image
        self.inlineData = try container.decodeIfPresent(Data.self, forKey: .data)
        self.dataFileName = try container.decodeIfPresent(String.self, forKey: .dataFileName)
        self.dataFilePath = nil
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let captureSource = try container.decodeIfPresent(CaptureSource.self, forKey: .captureSource) {
            self.captureSource = captureSource
        } else {
            self.captureSource = kind == .image ? .selectedRegion : nil
        }
        self.recordingFileName = try container.decodeIfPresent(String.self, forKey: .recordingFileName)
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.pixelSize = try container.decodeIfPresent(CGSize.self, forKey: .pixelSize)
        self.fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        self.recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
    }

    func resolvingImageFileDirectory(_ directoryURL: URL) -> ScreenshotItem {
        guard let dataFileName, inlineData == nil else {
            return self
        }

        let fileURL = directoryURL.appending(path: dataFileName)
        return replacingImageStorage(
            inlineData: nil,
            dataFileName: dataFileName,
            dataFilePath: fileURL.path,
            fileSize: fileSize,
            pixelSize: pixelSize ?? Self.imagePixelSize(at: fileURL)
        )
    }

    func replacingImageStorage(
        inlineData: Data?,
        dataFileName: String?,
        dataFilePath: String?,
        fileSize: Int64?,
        pixelSize: CGSize? = nil
    ) -> ScreenshotItem {
        ScreenshotItem(
            id: id,
            kind: kind,
            inlineData: inlineData,
            dataFileName: dataFileName,
            dataFilePath: dataFilePath,
            createdAt: createdAt,
            captureSource: captureSource,
            recordingFileName: recordingFileName,
            duration: duration,
            pixelSize: pixelSize ?? self.pixelSize,
            fileSize: fileSize,
            recognizedText: recognizedText
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(inlineData, forKey: .data)
        try container.encodeIfPresent(dataFileName, forKey: .dataFileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(captureSource, forKey: .captureSource)
        try container.encodeIfPresent(recordingFileName, forKey: .recordingFileName)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(pixelSize, forKey: .pixelSize)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(recognizedText, forKey: .recognizedText)
    }

    private init(
        id: UUID,
        kind: Kind,
        inlineData: Data?,
        dataFileName: String?,
        dataFilePath: String?,
        createdAt: Date,
        captureSource: CaptureSource?,
        recordingFileName: String?,
        duration: TimeInterval?,
        pixelSize: CGSize?,
        fileSize: Int64?,
        recognizedText: String?
    ) {
        self.id = id
        self.kind = kind
        self.inlineData = inlineData
        self.dataFileName = dataFileName
        self.dataFilePath = dataFilePath
        self.createdAt = createdAt
        self.captureSource = captureSource
        self.recordingFileName = recordingFileName
        self.duration = duration
        self.pixelSize = pixelSize
        self.fileSize = fileSize
        self.recognizedText = recognizedText
    }

    nonisolated private static func imagePixelSize(from data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
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
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}

enum ScreenshotImageFileStore {
    nonisolated static var defaultDirectoryURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appending(path: "ClipPixTran", directoryHint: .isDirectory)
            .appending(path: "ScreenshotImages", directoryHint: .isDirectory)
    }
}
