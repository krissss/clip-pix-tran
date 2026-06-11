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

    @Test func paragraphDisplayTextPreservesReadableStructure() {
        let text = "\r\n  标题\r\n\r\n  - 第一项\r\n    - 子项  \n\n结束\r\n"

        #expect(
            TranslationTextFormatting.paragraphDisplayText(text)
                == "  标题\n\n  - 第一项\n    - 子项  \n\n结束"
        )
    }

    @Test func paragraphDisplayTextAlignsTranslatedLineBreaksToSourceText() {
        let sourceText = """
        Providers

        Free Model OAuth
        Xiaomi MiMo Provider
        Extra Body Routing

        Plugin Market
        Plugin Extension Infrastructure
        """
        let translatedText = """
        供应商

        免费模型 OAuth

        小米 MiMo 提供商

        额外主体路由

        插件市场

        插件扩展基础设施
        """

        #expect(
            TranslationTextFormatting.paragraphDisplayText(translatedText, matching: sourceText)
                == """
                供应商

                免费模型 OAuth
                小米 MiMo 提供商
                额外主体路由

                插件市场
                插件扩展基础设施
                """
        )
    }

    @Test func paragraphDisplayTextKeepsProviderFormattingWhenLineCountsDiffer() {
        let sourceText = "First\nSecond"
        let translatedText = "第一\n\n第二\n\n第三"

        #expect(
            TranslationTextFormatting.paragraphDisplayText(translatedText, matching: sourceText)
                == "第一\n\n第二\n\n第三"
        )
    }
}
