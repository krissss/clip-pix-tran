import Foundation

enum ScreenshotCaptureCompletion: Equatable, Sendable {
    case recordOnly
    case copy
    case save
}

struct ScreenshotCaptureOutput: Equatable, Sendable {
    let data: Data
    let completion: ScreenshotCaptureCompletion

    nonisolated
    init(
        data: Data,
        completion: ScreenshotCaptureCompletion = .recordOnly
    ) {
        self.data = data
        self.completion = completion
    }
}

protocol ScreenshotService: Sendable {
    nonisolated func captureMainDisplay() async throws -> Data
    nonisolated func captureSelectedRegion() async throws -> ScreenshotCaptureOutput
}
