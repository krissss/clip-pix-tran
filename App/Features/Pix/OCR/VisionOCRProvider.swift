import Foundation
import ImageIO
import Vision

/// 基于原生 Vision 框架的 OCR provider。
///
/// Vision 的 `VNRecognizeTextRequest` 是同步阻塞 API，调用方应在脱离主线程的
/// `Task.detached` 中执行。本类型自身无状态、可安全跨 actor 使用。
nonisolated struct VisionOCRProvider: OCRProvider {
    func recognize(textIn data: Data) async throws -> OCRResult {
        guard !data.isEmpty,
              let cgImage = makeCGImage(from: data) else {
            throw OCRError.invalidImage
        }

        return try await Task.detached(priority: .userInitiated) { [cgImage] in
            try await Self.performRecognition(on: cgImage)
        }.value
    }

    private func makeCGImage(from data: Data) -> CGImage? {
        if let provider = CGDataProvider(data: data as CFData) {
            if let image = CGImage(
                pngDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) {
                return image
            }

            if let image = CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ) {
                return image
            }
        }

        // 回退：交给 AppKit/CG 解码任意格式。
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        return nil
    }

    private static func performRecognition(on cgImage: CGImage) async throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

        do {
            try VNSequenceRequestHandler().perform([request], on: cgImage)
        } catch {
            throw OCRError.underlying(error.localizedDescription)
        }

        let observations = request.results ?? []

        guard !observations.isEmpty else {
            throw OCRError.noTextRecognized
        }

        // 按从上到下、从左到右的阅读顺序排列。
        let sorted = observations.sorted { lhs, rhs in
            // Vision 坐标系 y 轴向上，boundingBox.origin.y 大的在上方。
            if abs(lhs.boundingBox.origin.y - rhs.boundingBox.origin.y) > 0.01 {
                return lhs.boundingBox.origin.y > rhs.boundingBox.origin.y
            }
            return lhs.boundingBox.origin.x < rhs.boundingBox.origin.x
        }

        let candidates = sorted.compactMap { $0.topCandidates(1).first }
        guard !candidates.isEmpty else {
            throw OCRError.noTextRecognized
        }

        let text = candidates.map(\.string).joined(separator: "\n")
        let averageConfidence = candidates.map(\.confidence).reduce(0, +) / Float(candidates.count)

        return OCRResult(text: text, confidence: averageConfidence)
    }
}
