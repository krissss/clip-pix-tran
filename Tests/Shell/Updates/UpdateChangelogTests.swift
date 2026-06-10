import Testing

@testable import ClipPixTran

@Suite("UpdateChangelog")
@MainActor
struct UpdateChangelogTests {
    private let sample = """
    # Changelog

    ## [Unreleased]

    - Work in progress

    ## [0.3.0] - 2026-06-10

    ### Added

    - 新增跨版本更新日志展示

    ## [0.2.0] - 2026-06-09

    ### Added

    - 添加首次启动引导

    ## [0.1.1] - 2026-06-07

    ### Fixed

    - 显示版本并本地化更新提示

    ## [0.1.0] - 2026-06-07

    ### Added

    - 首个版本
    """

    @Test("parseEntries parses released versions and skips unreleased")
    func parseEntriesSkipsUnreleased() {
        let entries = UpdateChangelog.parseEntries(in: sample)

        #expect(entries.map(\.version) == ["0.3.0", "0.2.0", "0.1.1", "0.1.0"])
        #expect(entries.first?.date == "2026-06-10")
        #expect(entries.first?.body.contains("跨版本更新日志") == true)
    }

    @Test("entries returns every version between current and latest")
    func rangeIncludesIntermediateVersions() {
        let entries = UpdateChangelog.entries(
            in: sample,
            from: "0.1.0",
            through: "0.3.0"
        )

        #expect(entries.map(\.version) == ["0.3.0", "0.2.0", "0.1.1"])
    }

    @Test("entries excludes current and newer than latest versions")
    func rangeExcludesCurrentAndFutureVersions() {
        let entries = UpdateChangelog.entries(
            in: sample,
            from: "0.1.1",
            through: "0.2.0"
        )

        #expect(entries.map(\.version) == ["0.2.0"])
    }

    @Test("version comparison handles v prefix and multi-digit components")
    func versionComparisonHandlesPrefixesAndMultiDigitComponents() {
        let markdown = """
        ## [0.10.0] - 2026-06-10

        - Newer

        ## [0.9.1] - 2026-06-09

        - Older
        """

        let entries = UpdateChangelog.entries(
            in: markdown,
            from: "v0.9.1",
            through: "v0.10.0"
        )

        #expect(entries.map(\.version) == ["0.10.0"])
    }
}
