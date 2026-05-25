import Foundation

struct PreviewScreenshotService: ScreenshotService {
    func captureMainDisplay() async throws -> Data {
        Data([0x89, 0x50, 0x4E, 0x47])
    }

    func captureSelectedRegion() async throws -> Data {
        Data([0x89, 0x50, 0x4E, 0x47])
    }
}

struct PreviewScreenshotPasteboardService: ScreenshotPasteboardService {
    func writePNGData(_ data: Data) throws {
    }
}

struct PreviewScreenshotFileSaver: ScreenshotFileSaving {
    func savePNGData(_ data: Data, suggestedFileName: String) throws {
    }
}
