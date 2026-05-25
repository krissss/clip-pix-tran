import Foundation

protocol ScreenshotService: Sendable {
    nonisolated func captureMainDisplay() async throws -> Data
    nonisolated func captureSelectedRegion() async throws -> Data
}
