import CoreGraphics
import Foundation

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
    let data: Data
    let createdAt: Date
    let captureSource: CaptureSource?
    let recordingFileName: String?
    let duration: TimeInterval?
    let pixelSize: CGSize?
    let fileSize: Int64?

    init(
        id: UUID = UUID(),
        data: Data,
        createdAt: Date = Date(),
        captureSource: CaptureSource = .selectedRegion
    ) {
        self.id = id
        self.kind = .image
        self.data = data
        self.createdAt = createdAt
        self.captureSource = captureSource
        self.recordingFileName = nil
        self.duration = nil
        self.pixelSize = nil
        self.fileSize = Int64(data.count)
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
        self.data = Data()
        self.createdAt = createdAt
        self.captureSource = nil
        self.recordingFileName = recordingFileName
        self.duration = duration
        self.pixelSize = pixelSize
        self.fileSize = fileSize
    }

    var isImage: Bool {
        kind == .image
    }

    var isRecording: Bool {
        kind == .recording
    }

    var recordingURL: URL? {
        guard let recordingFileName else {
            return nil
        }

        return ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: recordingFileName)
    }

    var byteCount: Int64 {
        switch kind {
        case .image:
            return Int64(data.count)
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
        case createdAt
        case captureSource
        case recordingFileName
        case duration
        case pixelSize
        case fileSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .image
        self.data = try container.decodeIfPresent(Data.self, forKey: .data) ?? Data()
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
    }
}
