import Foundation
import os
import Testing
@testable import ClipPixTran

@MainActor
struct OCRServiceTests {
    @Test func recognizesTextViaProvider() async throws {
        let service = OCRService(provider: StubOCRProvider { _ in
            OCRResult(text: "Hello", confidence: 0.9)
        })

        let result = try await service.recognize(imageData: Data([0x1]), itemID: UUID())

        #expect(result.text == "Hello")
        #expect(result.confidence == 0.9)
    }

    @Test func deduplicatesConcurrentRequestsForSameItem() async throws {
        let itemID = UUID()
        let provider = CountingOCRProvider { _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            return OCRResult(text: "counted", confidence: nil)
        }
        let service = OCRService(provider: provider)

        async let first = service.recognize(imageData: Data([0x1]), itemID: itemID)
        async let second = service.recognize(imageData: Data([0x1]), itemID: itemID)

        let results = try await (first, second)

        #expect(results.0.text == "counted")
        #expect(results.1.text == "counted")
        // 并发的两次调用应复用同一个任务，provider 只跑一次。
        #expect(provider.invocationCount == 1)
        #expect(service.status(for: itemID) == .done)
    }

    @Test func mapsUnderlyingErrorToOCRError() async {
        let itemID = UUID()
        let service = OCRService(provider: StubOCRProvider { _ in
            throw OCRError.invalidImage
        })

        await #expect(throws: OCRError.self) {
            try await service.recognize(imageData: Data([0x1]), itemID: itemID)
        }

        let status = service.status(for: itemID)
        guard case .failed(let error) = status else {
            Issue.record("expected failed status, got \(status)")
            return
        }
        #expect(error == .invalidImage)
    }

    @Test func reportsRecognizingStatusWhileInProgress() async throws {
        let itemID = UUID()
        let release = AsyncBox<Void>()
        let service = OCRService(provider: StubOCRProvider { _ in
            await release.value
            return OCRResult(text: "released", confidence: nil)
        })

        let task = Task {
            try await service.recognize(imageData: Data([0x1]), itemID: itemID)
        }

        // 等待任务进入 provider。
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.status(for: itemID) == .recognizing)

        release.fill(())
        let result = try await task.value
        #expect(result.text == "released")
        #expect(service.status(for: itemID) == .done)
    }

    @Test func noTextRecognizedIsSurfacedAsError() async {
        let itemID = UUID()
        let service = OCRService(provider: StubOCRProvider { _ in
            throw OCRError.noTextRecognized
        })

        await #expect(throws: OCRError.self) {
            try await service.recognize(imageData: Data([0x1]), itemID: itemID)
        }

        #expect(service.status(for: itemID) == .failed(.noTextRecognized))
    }
}

// MARK: - Test Doubles

private struct StubOCRProvider: OCRProvider {
    let body: @Sendable (Data) async throws -> OCRResult

    func recognize(textIn data: Data) async throws -> OCRResult {
        try await body(data)
    }
}

private final class CountingOCRProvider: OCRProvider, @unchecked Sendable {
    let body: @Sendable (Data) async throws -> OCRResult
    private let count = OSAllocatedUnfairLock(initialState: 0)

    init(body: @escaping @Sendable (Data) async throws -> OCRResult) {
        self.body = body
    }

    var invocationCount: Int {
        count.withLock { $0 }
    }

    func recognize(textIn data: Data) async throws -> OCRResult {
        count.withLock { $0 += 1 }
        return try await body(data)
    }
}

/// 用于阻塞 provider 直到测试方放行。
private final class AsyncBox<T>: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<T?>(initialState: nil)

    func fill(_ newValue: T) {
        storage.withLock { $0 = newValue }
    }

    var value: T {
        get async {
            while true {
                if let current = storage.withLock({ $0 }) {
                    return current
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }
}
