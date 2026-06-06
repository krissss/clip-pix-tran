import Testing
@testable import ClipPixTran

struct TranslationTextFormattingTests {
    @Test func compactDisplayTextNormalizesNewlinesAndRemovesBlankLines() {
        let text = "\r\n  第一行  \r\n\r\n第二行\n   \n第三行"

        #expect(TranslationTextFormatting.compactDisplayText(text) == "第一行\n第二行\n第三行")
    }

    @Test func compactDisplayLinesKeepsNonEmptyLinesOnly() {
        let text = " hello \n\nworld\r\n  \r done "

        #expect(TranslationTextFormatting.compactDisplayLines(text) == ["hello", "world", "done"])
    }
}
