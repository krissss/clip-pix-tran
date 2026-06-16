import CoreGraphics
import Foundation

enum ScreenshotRegionCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case screenshot
    case recording

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot:
            L10n.pixScreenshot
        case .recording:
            L10n.pixRecording
        }
    }

    var systemImage: String {
        switch self {
        case .screenshot:
            "camera.viewfinder"
        case .recording:
            "record.circle"
        }
    }
}

enum ScreenshotCaptureCompletion: Equatable, Sendable {
    case recordOnly
    case copy
    case save
    case pinToScreen
    case startRecording
    case recognizeText
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
    nonisolated func ensureScreenCaptureAccess() async throws
    nonisolated func captureMainDisplay() async throws -> Data
    nonisolated func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async throws -> ScreenshotCaptureOutput
}

extension ScreenshotService {
    nonisolated func ensureScreenCaptureAccess() async throws {
    }

    nonisolated func captureSelectedRegion() async throws -> ScreenshotCaptureOutput {
        try await captureSelectedRegion(initialMode: .screenshot)
    }
}
