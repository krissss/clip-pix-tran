import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct L10nTests {
    @Test func switchingLanguageUpdatesDisplayedStrings() {
        let suiteName = "ClipPixTranTests.L10n.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preference = LocalizationPreference(defaults: defaults)
        preference.updateLanguage(.english)
        #expect(preference.language == .english)

        #expect(L10n.tr("app.name", "", languageCode: "en") == "ClipPixTran")
        #expect(L10n.tr("app.settings", "", languageCode: "en") == "Settings")
        #expect(
            L10n.format(
                "settings.launchAtLogin",
                "",
                languageCode: "en",
                "ClipPixTran"
            ) == "Launch ClipPixTran at Login"
        )
        #expect(
            L10n.format(
                "onboarding.windowTitle",
                "",
                languageCode: "en",
                "ClipPixTran"
            ) == "ClipPixTran Ready"
        )

        preference.updateLanguage(.simplifiedChinese)
        #expect(preference.language == .simplifiedChinese)

        #expect(L10n.tr("app.name", "", languageCode: "zh-Hans") == "ClipPixTran")
        #expect(L10n.tr("app.settings", "", languageCode: "zh-Hans") == "设置")
        #expect(
            L10n.format(
                "settings.launchAtLogin",
                "",
                languageCode: "zh-Hans",
                "ClipPixTran"
            ) == "开机时启动 ClipPixTran"
        )
        #expect(
            L10n.format(
                "onboarding.windowTitle",
                "",
                languageCode: "zh-Hans",
                "ClipPixTran"
            ) == "ClipPixTran 准备使用"
        )
    }

}
