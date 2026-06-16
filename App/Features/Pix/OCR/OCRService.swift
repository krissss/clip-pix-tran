import Foundation

/// OCR 服务的对外门面。
///
/// 职责：持有当前 provider、对同一图片的并发识别做去重（避免重复跑）、
/// 把底层错误归一成 `OCRError`。本期 provider 固定为 `VisionOCRProvider`。
@MainActor
@Observable
final class OCRService {
    /// 单张图片的识别状态，供 UI 观察进度。
    enum Status: Equatable {
        case idle
        case recognizing
        case done
        case failed(OCRError)
    }

    private let provider: OCRProvider
    /// 进行中的识别任务，按图片 id 去重。
    private var inFlightTasks: [UUID: Task<OCRResult, Error>] = [:]
    /// 各图片当前状态。
    private(set) var statuses: [UUID: Status] = [:]

    var descriptor: OCRProviderDescriptor {
        .vision
    }

    nonisolated init(provider: OCRProvider = VisionOCRProvider()) {
        self.provider = provider
    }

    func status(for itemID: UUID) -> Status {
        statuses[itemID] ?? .idle
    }

    /// 识别图片文字。对同一张图的并发调用会复用同一个进行中的任务。
    func recognize(imageData: Data, itemID: UUID) async throws -> OCRResult {
        if let existing = inFlightTasks[itemID] {
            return try await existing.value
        }

        statuses[itemID] = .recognizing
        let provider = provider
        let task = Task<OCRResult, Error>.detached(priority: .userInitiated) {
            try await provider.recognize(textIn: imageData)
        }
        inFlightTasks[itemID] = task

        do {
            let result = try await task.value
            statuses[itemID] = .done
            inFlightTasks[itemID] = nil
            return result
        } catch let error as OCRError {
            statuses[itemID] = .failed(error)
            inFlightTasks[itemID] = nil
            throw error
        } catch {
            let mapped = OCRError.underlying(error.localizedDescription)
            statuses[itemID] = .failed(mapped)
            inFlightTasks[itemID] = nil
            throw mapped
        }
    }
}
