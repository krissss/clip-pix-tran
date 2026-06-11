import SwiftUI

struct CompactTranslationText: View {
    let text: String
    var referenceText: String? = nil
    var font: Font = .body
    var foregroundColor: Color?
    var maxDisplayLines: Int?
    var lineLimitPerDisplayLine: Int?
    var lineSpacing: CGFloat = 2
    var enableSelection = false
    var preservesParagraphFormatting = false

    private var lines: [String] {
        let compactLines = TranslationTextFormatting.compactDisplayLines(text)
        if let maxDisplayLines {
            return Array(compactLines.prefix(maxDisplayLines))
        }
        return compactLines
    }

    private var paragraphText: String {
        TranslationTextFormatting.paragraphDisplayText(text, matching: referenceText)
    }

    var body: some View {
        Group {
            if preservesParagraphFormatting {
                lineView(paragraphText)
            } else {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if enableSelection {
            Text(verbatim: line)
                .font(font)
                .foregroundStyle(foregroundColor ?? .primary)
                .lineSpacing(preservesParagraphFormatting ? lineSpacing : 0)
                .lineLimit(lineLimitPerDisplayLine)
                .textSelection(.enabled)
        } else {
            Text(verbatim: line)
                .font(font)
                .foregroundStyle(foregroundColor ?? .primary)
                .lineSpacing(preservesParagraphFormatting ? lineSpacing : 0)
                .lineLimit(lineLimitPerDisplayLine)
        }
    }
}
