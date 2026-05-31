import CoreGraphics
import Foundation

enum ScreenshotCaptureCompletion: Equatable, Sendable {
    case recordOnly
    case copy
    case save
    case pinToScreen
}

struct ScreenshotCaptureOutput: Equatable, Sendable {
    let data: Data
    let completion: ScreenshotCaptureCompletion
    let sourceRect: CGRect?

    nonisolated
    init(
        data: Data,
        completion: ScreenshotCaptureCompletion = .recordOnly,
        sourceRect: CGRect? = nil
    ) {
        self.data = data
        self.completion = completion
        self.sourceRect = sourceRect
    }
}

protocol ScreenshotService: Sendable {
    nonisolated func captureMainDisplay() async throws -> Data
    nonisolated func captureSelectedRegion() async throws -> ScreenshotCaptureOutput
}
