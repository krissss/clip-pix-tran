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
        #expect(L10n.tr("app.quit", "", languageCode: "en") == "Quit")
        #expect(L10n.tr("settings.launchAtLogin", "", languageCode: "en") == "Launch at Login")
        #expect(L10n.tr("onboarding.windowTitle", "", languageCode: "en") == "Ready")

        preference.updateLanguage(.simplifiedChinese)
        #expect(preference.language == .simplifiedChinese)

        #expect(L10n.tr("app.name", "", languageCode: "zh-Hans") == "ClipPixTran")
        #expect(L10n.tr("app.settings", "", languageCode: "zh-Hans") == "设置")
        #expect(L10n.tr("app.quit", "", languageCode: "zh-Hans") == "退出")
        #expect(L10n.tr("settings.launchAtLogin", "", languageCode: "zh-Hans") == "开机时启动")
        #expect(L10n.tr("onboarding.windowTitle", "", languageCode: "zh-Hans") == "准备使用")
    }

}
