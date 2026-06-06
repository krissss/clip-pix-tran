import AppKit
import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct SystemClipboardServiceTests {
    @Test func preservesFormattedTextPayloads() throws {
        let pasteboardName = NSPasteboard.Name("ClipPixTranTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: pasteboardName)
        defer {
            pasteboard.clearContents()
        }

        let htmlType = NSPasteboard.PasteboardType.html
        let htmlData = try #require("<table><tr><td>A1</td></tr></table>".data(using: .utf8))

        pasteboard.clearContents()
        pasteboard.setString("A1", forType: .string)
        pasteboard.setData(htmlData, forType: htmlType)

        let service = SystemClipboardService(pasteboard: pasteboard)
        let item = try #require(service.readItem())

        #expect(item.kind == .text)
        #expect(item.text == "A1")
        #expect(item.payloads.contains(ClipboardPayload(type: htmlType.rawValue, data: htmlData)))

        pasteboard.clearContents()
        try service.writeItem(item)

        #expect(pasteboard.string(forType: .string) == "A1")
        #expect(pasteboard.data(forType: htmlType) == htmlData)
    }

    @Test func selectsRichTextPayloadForPreview() throws {
        let plainData = try #require("plain".data(using: .utf8))
        let htmlData = try #require("<table><tr><td>A1</td></tr></table>".data(using: .utf8))
        let rtfData = try #require("{\\rtf1 A1}".data(using: .utf8))

        let item = ClipboardItem(
            text: "A1",
            payloads: [
                ClipboardPayload(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtfData),
                ClipboardPayload(type: NSPasteboard.PasteboardType.string.rawValue, data: plainData),
                ClipboardPayload(type: NSPasteboard.PasteboardType.html.rawValue, data: htmlData)
            ]
        )

        let previewData = try #require(item.richTextPreviewData)
        #expect(previewData.format == .html)
        #expect(previewData.data == htmlData)
    }

    @Test func sniffsPreviewImageExtension() {
        #expect(SystemImagePreviewService.imageFileExtension(from: Data([0x89, 0x50, 0x4E, 0x47])) == "png")
        #expect(SystemImagePreviewService.imageFileExtension(from: Data([0xFF, 0xD8, 0xFF])) == "jpg")
        #expect(SystemImagePreviewService.imageFileExtension(from: Data("GIF89a".utf8)) == "gif")
        #expect(SystemImagePreviewService.imageFileExtension(from: Data([0x49, 0x49, 0x2A, 0x00])) == "tiff")

        var heicData = Data([0x00, 0x00, 0x00, 0x18])
        heicData.append(contentsOf: Data("ftypheic".utf8))
        #expect(SystemImagePreviewService.imageFileExtension(from: heicData) == "heic")
    }

    @Test func writesScreenshotItemPreviewURL() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let item = ScreenshotItem(id: UUID(), data: data)
        let url = try #require(SystemImagePreviewService.imageURL(for: item))

        #expect(url.lastPathComponent.hasPrefix("screenshot-\(item.id.uuidString)"))
        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == data)
    }
}
