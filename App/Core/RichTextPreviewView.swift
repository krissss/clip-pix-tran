import AppKit
import SwiftUI

struct RichTextPreviewView: NSViewRepresentable {
    let text: String
    let richTextData: ClipboardRichTextPreviewData?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(attributedText())
    }

    private func attributedText() -> NSAttributedString {
        if let richTextData,
           let attributedString = Self.makeAttributedString(from: richTextData) {
            return attributedString
        }

        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private static func makeAttributedString(from previewData: ClipboardRichTextPreviewData) -> NSAttributedString? {
        switch previewData.format {
        case .html:
            return makeHTMLAttributedString(from: previewData.data)
        case .rtf:
            return NSAttributedString(
                rtf: previewData.data,
                documentAttributes: nil
            )
        case .rtfd:
            return NSAttributedString(
                rtfd: previewData.data,
                documentAttributes: nil
            )
        }
    }

    private static func makeHTMLAttributedString(from data: Data) -> NSAttributedString? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributedString = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) {
            return attributedString
        }

        guard let string = String(data: data, encoding: .utf8),
              let repairedData = string.data(using: .utf8) else {
            return nil
        }

        return try? NSAttributedString(
            data: repairedData,
            options: options,
            documentAttributes: nil
        )
    }
}
