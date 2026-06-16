import Foundation
import Testing
@testable import ClipPixTran

struct ScreenshotItemFilteredTests {
    @Test func matchesByRecognizedText() throws {
        let match = makeItem(recognizedText: "Invoice #1024")
        let other = makeItem(recognizedText: "Screenshot of desktop")

        let filtered = [match, other].filtered(matching: "invoice")

        #expect(filtered.map(\.id) == [match.id])
    }

    @Test func matchIsCaseInsensitive() throws {
        let item = makeItem(recognizedText: "Invoice 1024")

        let filtered = [item].filtered(matching: "INVOICE")

        #expect(filtered.map(\.id) == [item.id])
    }

    @Test func ignoresItemsWithoutRecognizedTextWhenQueryTargetsText() throws {
        let withoutText = makeItem(recognizedText: nil)

        let filtered = [withoutText].filtered(matching: "some unmatched token 999")

        #expect(filtered.isEmpty)
    }

    @Test func emptyQueryReturnsAllItems() throws {
        let first = makeItem(recognizedText: nil)
        let second = makeItem(recognizedText: "hello")

        let filtered = [first, second].filtered(matching: "   ")

        #expect(filtered.count == 2)
    }

    private func makeItem(recognizedText: String?) -> ScreenshotItem {
        var item = ScreenshotItem(data: Data([0x1, 0x2, 0x3]))
        item.recognizedText = recognizedText
        return item
    }
}
