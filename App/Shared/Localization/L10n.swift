import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            L10n.languageSystem
        case .english:
            "English"
        case .simplifiedChinese:
            "中文"
        }
    }
}

@Observable
final class LocalizationPreference {
    private let defaults: UserDefaults
    private static let languageKey = "app.language"

    private(set) var language: AppLanguage
    private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = Self.storedLanguage(defaults: defaults)
    }

    func updateLanguage(_ language: AppLanguage) {
        guard self.language != language else {
            return
        }

        self.language = language
        defaults.set(language.rawValue, forKey: Self.languageKey)
        version += 1
        NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)
    }

    static var currentLanguage: AppLanguage {
        storedLanguage(defaults: .standard)
    }

    static var effectiveLanguageCode: String {
        switch currentLanguage {
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        case .system:
            Locale.current.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        }
    }

    static let languageDidChangeNotification = Notification.Name("LocalizationPreference.languageDidChange")

    private static func storedLanguage(defaults: UserDefaults) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: languageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }

        return language
    }
}

enum L10n {
    static func tr(_ key: String, _ defaultValue: String) -> String {
        let languageCode = LocalizationPreference.effectiveLanguageCode
        return tr(key, defaultValue, languageCode: languageCode)
    }

    static func tr(_ key: String, _ defaultValue: String, languageCode: String) -> String {
        return tables[languageCode]?[key] ?? defaultValue
    }

    static func format(_ key: String, _ defaultValue: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key, defaultValue), arguments: arguments)
    }

    static func format(
        _ key: String,
        _ defaultValue: String,
        languageCode: String,
        _ arguments: CVarArg...
    ) -> String {
        String(format: tr(key, defaultValue, languageCode: languageCode), arguments: arguments)
    }

    private static let tables: [String: [String: String]] = [
        "en": [
            "app.name": "ClipPixTran",
            "app.settings": "Settings",
            "app.openSettings": "Open Settings",
            "app.debugBuild": "Debug Build",
            "app.debugBuild.title": "Debug Build",
            "app.quit": "Quit",
            "app.reopenOnboarding": "Reopen Onboarding",

            "language.header": "Language",
            "language.system": "Follow System",
            "settings.general": "General",
            "settings.shortcuts": "Shortcuts",
            "settings.about": "About",
            "settings.startup": "Startup",
            "settings.launchAtLogin": "Launch at Login",
            "settings.dock": "Dock",
            "settings.interfaceLanguage": "Interface Language",
            "settings.hideDockIcon": "Hide Dock Icon After Closing Main Window",
            "settings.onboarding": "Onboarding",
            "settings.firstLaunchOnboarding": "First Launch Onboarding",
            "settings.reopen": "Reopen",
            "settings.generalFootnote": "When Dock hiding is enabled, the app stays in the menu bar after the main window closes. You can reopen onboarding anytime.",
            "settings.globalShortcuts": "Global Shortcuts",
            "settings.history": "History",
            "settings.persistClipboardHistory": "Keep Clipboard History After Relaunch",
            "settings.normalHistoryLimit": "Normal History Limit",
            "settings.clipHistoryFootnote": "When history persistence is disabled, the saved clipboard history file is deleted.",
            "settings.persistScreenshotHistory": "Keep Screenshot History After Relaunch",
            "settings.screenshotHistoryLimit": "Screenshot History Limit",
            "settings.pixHistoryFootnote": "Screenshots may contain sensitive information. When persistence is enabled, recent screenshots are saved locally in the app support folder.",
            "settings.defaultLanguages": "Default Languages",
            "settings.defaultSourceLanguage": "Default Source Language",
            "settings.defaultTargetLanguage": "Default Target Language",
            "settings.translationServices": "Translation Services",
            "settings.speechServices": "Speech Services",
            "settings.defaultSpeech": "Default Speech",
            "settings.persistTranslationHistory": "Keep Translation History After Relaunch",
            "settings.translationHistoryLimit": "Translation History Limit",
            "settings.tranFootnote": "The target language follows the system by default. Speech uses the system voice by default. Translation history is saved locally.",
            "settings.updates": "Updates",
            "settings.currentVersion": "Current Version",
            "settings.autoCheckUpdates": "Check for Updates Automatically",
            "settings.autoDownloadUpdates": "Download Updates Automatically",
            "settings.checkFrequency": "Check Frequency",
            "settings.lastChecked": "Last Checked",
            "settings.checkUpdates": "Check for Updates",
            "settings.unknown": "Unknown",
            "settings.neverChecked": "Never",

            "shortcut.mainWindow": "Open Main Window",
            "shortcut.clipboardPanel": "Clipboard Quick Panel",
            "shortcut.pixCapture": "Pix Capture",
            "shortcut.translateSelection": "Translate Selected Text",
            "shortcut.record": "Record Shortcut",
            "shortcut.press": "Press Shortcut",

            "common.cancel": "Cancel",
            "common.delete": "Delete",
            "common.copy": "Copy",
            "common.save": "Save",
            "common.preview": "Preview",
            "common.done": "Done",
            "common.export": "Export",
            "common.clearHistory": "Clear History",
            "common.empty": "Empty",
            "common.search.clear": "Clear Search",
            "common.openSystemSettings": "Open System Settings",
            "common.records.count": "%d records",
            "common.items.count": "%d items",
            "common.records.filteredCount": "%d/%d records",
            "common.fileItems.more": "%@ and %d items",
            "common.favorite": "Pin",
            "common.unfavorite": "Unpin",
            "common.copyPlainText": "Copy Plain Text",
            "common.translate": "Translate",
            "common.revealInFinder": "Show in Finder",
            "common.pinToScreen": "Pin to Screen",
            "common.exportMP4": "Export MP4",
            "common.exportGIF": "Export GIF",
            "common.zoomOut": "Zoom Out",
            "common.zoomIn": "Zoom In",
            "common.fitWindow": "Fit to Window",
            "common.copyImage": "Copy Image",
            "common.saveImage": "Save Image",
            "common.cannotPreviewImage": "Cannot Preview Image",
            "common.close": "Close",
            "common.select": "Select",
            "common.plainText": "Plain Text",
            "common.deleteRecord": "Delete Record",
            "common.pinWindow": "Pin Window",
            "common.unpinWindow": "Unpin Window",
            "common.previous": "Previous",
            "common.next": "Next",
            "common.later": "Later",
            "common.ok": "OK",
            "kind.text": "Text",
            "kind.image": "Image",
            "kind.file": "File",
            "clip.clearTitle": "Clear Clipboard History?",
            "clip.clearMessage": "This deletes all clipboard history and cannot be undone.",
            "clip.search": "Search Clipboard History",
            "clip.history": "Clipboard History",
            "clip.empty": "No Clipboard Items",
            "clip.noResults": "No Matching Items",
            "clip.selectItem": "Select an Item",
            "clip.clearHelp": "Clear Clipboard History",
            "clip.openFull": "Open Full Clipboard",
            "clip.paste": "Paste",
            "clip.copyBack": "Copy Back to Clipboard",
            "clip.sendToTran": "Send to Tran",
            "clip.lastCopied": "Last Copied",
            "clip.characterCount": "Characters",
            "clip.formatCount": "Formats",
            "clip.itemCount": "Items",
            "clip.textPreview": "Text Preview",
            "clip.richText": "Rich Text",
            "clip.keepsFormatting": "Keeps Formatting",
            "clip.textSummary": "Text · %d characters",
            "clip.richTextSummary": "Rich Text · %d characters · %d formats",
            "clip.previewableImage": "Image · Preview Available",
            "clip.pathSummary": "%@ · %@ and %d items",

            "relative.justNow": "Just now",
            "relative.minutesAgo": "%d min ago",
            "relative.hoursAgo": "%d hr ago",
            "relative.daysAgo": "%d days ago",
            "pix.clearTitle": "Clear Pix History?",
            "pix.clearMessage": "This deletes all screenshot and recording history and cannot be undone.",
            "pix.search": "Search Pix History",
            "pix.history": "Pix History",
            "pix.empty": "No Screenshots Yet",
            "pix.noResults": "No Matching Pix Items",
            "pix.clearHelp": "Clear Screenshot History",
            "pix.pngImage": "PNG Image",
            "pix.mp4Recording": "MP4 Recording",
            "pix.recording": "Recording",
            "pix.fullScreen": "Full Screen",
            "pix.screenshot": "Screenshot",
            "pix.captureSelected": "Screenshot",
            "pix.captureSelected.help": "Drag to select a screen region for a screenshot",
            "pix.recordSelected": "Record",
            "pix.recordSelected.help": "Drag to select a screen region and start recording",
            "pix.captureFullScreen.help": "Capture the main display",
            "pix.cancelSelection": "Cancel Selection",
            "pix.cancelSelection.help": "End the current selection",
            "pix.saving": "Saving",
            "pix.stopRecording": "Stop Recording",
            "pix.stopRecording.help": "Stop and save the current recording",
            "pix.copyScreenshot": "Copy Screenshot",
            "pix.saveScreenshot": "Save Screenshot",
            "pix.openInPreview": "Open Screenshot in Preview.app",
            "pix.openRecording": "Open Recording",
            "pix.deleteScreenshot": "Delete Screenshot",
            "pix.imagePreview": "Image Preview",
            "pix.recordingPreview": "Recording Preview",
            "pix.details": "Details",
            "pix.type": "Type",
            "pix.createdAt": "Created",
            "pix.fileSize": "File Size",
            "pix.duration": "Duration",
            "pix.dimensions": "Dimensions",
            "pix.ocr.section": "Recognized Text",
            "pix.ocr.extract": "Extract Text",
            "pix.ocr.extract.help": "Recognize text in this screenshot",
            "pix.ocr.recognizing": "Recognizing…",
            "pix.ocr.empty": "No text recognized yet. Extract text from this screenshot to copy, translate, or search later.",
            "pix.ocr.noText": "No text was found in this screenshot.",
            "pix.ocr.recognizeAgain": "Re-extract",
            "pix.ocr.recognizeAgain.help": "Run text recognition again",
            "pix.ocr.save": "Save",
            "pix.ocr.translate": "Translate",
            "pix.ocr.copyText": "Copy Text",
            "pix.ocr.tool": "Recognize Text",
            "pix.ocr.tool.help": "Recognize text in the selected region and copy it",
            "pix.ocr.invalidImage": "Couldn't read this image.",
            "pix.ocr.noTextRecognized": "No text was recognized.",
            "pix.ocr.recognizedCopied": "Text recognized and copied.",
            "gif.exportTitle": "Export GIF",
            "gif.frameCount": "%d frames",
            "gif.previewFrameCount": "%d-frame preview",
            "gif.truncatedPreview": "%d frames · first %@",
            "gif.frameRate": "Frame Rate",
            "gif.speed": "Speed",
            "gif.maxDimension": "Max Dimension",
            "gif.maxFrames": "Max Frames",
            "gif.frameUnit": "frames",
            "capture.mode": "Capture Mode",
            "capture.tool.move": "Move",
            "capture.tool.rectangle": "Rectangle",
            "capture.tool.ellipse": "Ellipse",
            "capture.tool.arrow": "Arrow",
            "capture.tool.pen": "Pen",
            "capture.tool.text": "Text",
            "capture.tool.mosaic": "Mosaic",
            "capture.undo": "Undo",
            "capture.redo": "Redo",
            "capture.startRecording": "Start Recording",
            "capture.mosaicMode": "Mosaic Mode",
            "capture.mosaicBlockSize": "Block Size",
            "capture.mosaicBrushSize": "Brush Size",
            "capture.color": "Color",
            "capture.lineWidth": "Line Width",
            "capture.fontSize": "Font Size",
            "language.autoDetect": "Auto Detect",
            "language.zhHans": "Simplified Chinese",
            "language.zhHant": "Traditional Chinese",
            "language.english": "English",
            "language.japanese": "Japanese",
            "language.korean": "Korean",
            "language.french": "French",
            "language.german": "German",
            "tran.clearTitle": "Clear Translation History?",
            "tran.clearMessage": "This deletes all translation history and cannot be undone.",
            "tran.textTranslation": "Text Translation",
            "tran.translate": "Translate",
            "tran.sourceText": "Source",
            "tran.speakSource": "Speak Source",
            "tran.result": "Translation Result",
            "tran.providerCount": "%d services",
            "tran.sourceLanguage": "Source Language",
            "tran.targetLanguage": "Target Language",
            "tran.swapLanguages": "Swap Languages",
            "tran.autoDetectedLanguage": "Auto: %@",
            "tran.emptyHistory": "No Translation History Yet",
            "tran.searchHistory": "Search Translation History",
            "tran.noResults": "No Matching Translations",
            "tran.history": "Translation History",
            "tran.clearHelp": "Clear Translation History",
            "tran.loadHistory": "Load This Translation",
            "tran.deleteHistory": "Delete Translation",
            "tran.switchProvider": "Switch to %@",
            "tran.localProvider": "Local",
            "tran.retry": "Translate Again",
            "tran.speakTranslation": "Speak Translation",
            "tran.stopSpeaking": "Stop Speaking",
            "tran.copyTranslation": "Copy Translation",
            "tran.inputSource": "Enter Source",
            "tran.readingSelection": "Reading Selected Text...",
            "tran.selectionTranslation": "Selection Translation",
            "tran.copySource": "Copy Source",
            "tran.openFull": "Open Full Translation",
            "tran.expandQuickPanel": "Expand Panel",
            "tran.collapseQuickPanel": "Collapse Panel",
            "tran.changeSourceLanguage": "Change Source Language",
            "tran.changeTargetLanguage": "Change Target Language",
            "tran.characterCount": "%d chars",
            "tran.quickPanelShortcut": "Enter Translate / ⌘↩ New Line",
            "tran.retranslateCurrentSource": "Translate Current Source Again",
            "tran.noProviders": "No Translation Services",
            "tran.detectedSummary": "Detected: %@ · %@",
            "tran.defaultIdleMessage": "Enter text and click Translate. Results will appear here.",
            "tran.historyIdleMessage": "After loading history, click Translate to refresh other providers.",
            "tran.disabledProviderMessage": "This provider is disabled in Settings.",
            "tran.translating": "Translating...",
            "tran.speechFailed": "Speech failed: %@",
            "tran.emptySourceError": "Enter text to translate.",
            "tran.providerUnavailable": "The translation service is unavailable. Try again later or check the system language package.",
            "tran.providerNoneEnabled": "Enable at least one translation provider.",
            "speech.providerUnavailable": "The speech service is unavailable. Try again later or check the speech provider configuration.",
            "speech.requestFailed": "Speech service request failed (HTTP %d).",
            "textSelection.noSelection": "No selected text was detected.",
            "clipboard.writeFailed": "Could not write to the clipboard.",
            "screenshot.permissionDenied": "Could not read the screen. Allow %@ to record the screen in System Settings, then restart the app.",
            "screenshot.missingEntitlements": "This build is missing the required screen recording permission configuration.",
            "screenshot.displayNotFound": "Could not locate the display to capture.",
            "screenshot.timedOut": "The screenshot request timed out. Try again.",
            "screenshot.unavailable": "Could not capture the current screen.",
            "screenshot.pngEncodingFailed": "The screenshot was created but could not be converted to PNG.",
            "screenshot.invalidImageData": "Could not recognize this screenshot.",
            "screenshot.missingDestination": "No save location was selected.",
            "screenshot.pinFailed": "Could not pin this screenshot.",
            "screenshot.closePinned": "Close Pinned Screenshot",
            "recording.missingFile": "Could not find the recording file.",
            "recording.outputRejected": "Could not create the recording output.",
            "recording.didNotFinish": "The recording file timed out while writing. Try again.",
            "recording.gifDestinationFailed": "Could not create the GIF file.",
            "recording.gifFrameGenerationFailed": "Could not generate GIF frames from the recording.",
            "recording.cancel": "Cancel Recording",
            "launchAtLogin.disabledMessage": "When disabled, this app will not start automatically when you log in.",
            "launchAtLogin.enabledMessage": "Enabled. This app will start automatically when you log in.",
            "launchAtLogin.requiresApprovalMessage": "Launch at login was requested. Allow this app in System Settings login items.",
            "launchAtLogin.unavailableMessage": "This build cannot register as a login item.",
            "launchAtLogin.updateFailed": "Could not update launch at login: %@",
            "onboarding.windowTitle": "Ready",
            "onboarding.ready": "Ready",
            "onboarding.skipNote": "You can skip onboarding and reopen it later from Settings.",
            "onboarding.screenRecordingExplanation": "Pix needs screen access for screenshots, region selection, and recording.",
            "onboarding.accessibilityExplanation": "Tran needs Accessibility permission to read selected text. Pix also uses it to identify windows and controls.",
            "onboarding.shortcutsExplanation": "Confirm your common global shortcuts. These use the same settings page configuration and can be changed later.",
            "onboarding.authorizeScreenRecording": "Authorize Screen Recording",
            "onboarding.recheck": "Recheck",
            "onboarding.skip": "Skip Onboarding",
            "onboarding.screenRecordingAuthorizedMessage": "Screen Recording permission is authorized.",
            "onboarding.screenRecordingPromptFallbackOpenedSettings": "The system did not show a permission prompt. System Settings has been opened; allow %@ to record the screen, then recheck.",
            "onboarding.screenRecordingPromptFallbackManual": "The system did not show a permission prompt. Go to Privacy & Security > Screen Recording, allow %@, then recheck.",
            "onboarding.settingsOpenedRecheck": "System Settings is open. After granting permission, return here and click Recheck.",
            "onboarding.accessibilitySettingsOpened": "System Settings is open. After enabling %@, return here and click Recheck.",
            "onboarding.screenRecordingSettingsOpenFailed": "Could not open System Settings. Go to Privacy & Security > Screen Recording manually.",
            "onboarding.accessibilitySettingsOpenFailed": "Could not open System Settings. Go to Privacy & Security > Accessibility manually.",
            "onboarding.screenRecordingTitle": "Allow Screen Recording",
            "onboarding.accessibilityTitle": "Allow Accessibility",
            "onboarding.shortcutsTitle": "Confirm Global Shortcuts",
            "onboarding.screenRecordingSubtitle": "For Pix screenshots, region selection, and recording",
            "onboarding.accessibilitySubtitle": "For reading selected text and identifying window controls",
            "onboarding.shortcutsSubtitle": "Make common actions available anywhere",
            "onboarding.adjustable": "Adjustable",
            "onboarding.authorized": "Authorized",
            "onboarding.notAuthorized": "Not Authorized",
            "onboarding.capabilityReady": "This capability is ready.",
            "onboarding.capabilityNeedsPermission": "Grant permission for the full experience.",
            "update.checkingProgress": "Checking for updates...",
            "update.downloadingProgress": "Downloading update...",
            "update.extractingProgress": "Preparing update...",
            "update.readyToInstallMessage": "The update is ready. The app will relaunch after installation.",
            "update.installingProgress": "Installing update...",
            "update.installedMessage": "The update has been installed.",
            "update.alreadyLatestMessage": "The app is up to date.",
            "update.checkFailedMessage": "Could not complete the update check.",
            "update.skipVersion": "Skip This Version",
            "update.releaseNotes": "Release Notes",
            "update.titleAlreadyLatest": "Up to Date",
            "update.titleFailed": "Update Failed",
            "update.titleReadyToInstall": "Ready to Install",
            "update.titleInstalling": "Installing Update...",
            "update.titleInstalled": "Update Installed",
            "update.windowTitle": "Updates",
            "update.availableTitle": "%@ Available",
            "update.versionSubtitle": "Current %@ -> Latest %@",
            "update.installAndRelaunch": "Install and Relaunch",
            "update.install": "Install Update",
            "update.downloadedMessage": "The update has been downloaded.",
            "update.unavailableDebugBuild": "Debug builds do not check for updates. Use a Release build to test updates.",
            "update.availableStatus": "Automatic updates are available for this build.",
            "update.unavailableConfiguration": "Automatic updates are not configured for this build.",
            "update.unavailableAlertTitle": "Automatic Updates Not Configured",
            "update.unavailableAlertMessage": "This build does not include the update configuration required to check for updates.",
            "update.frequency.daily": "Daily",
            "update.frequency.weekly": "Weekly",
            "update.frequency.monthly": "Monthly",
        ],
        "zh-Hans": [
            "app.name": "ClipPixTran",
            "app.settings": "设置",
            "app.openSettings": "打开设置",
            "app.debugBuild": "Debug 构建",
            "app.debugBuild.title": "Debug 构建",
            "app.quit": "退出",
            "app.reopenOnboarding": "重新打开引导",

            "language.header": "语言",
            "language.system": "跟随系统",
            "settings.general": "通用",
            "settings.shortcuts": "快捷键",
            "settings.about": "关于",
            "settings.startup": "启动",
            "settings.launchAtLogin": "开机时启动",
            "settings.dock": "Dock",
            "settings.interfaceLanguage": "界面语言",
            "settings.hideDockIcon": "关闭主窗口后隐藏 Dock 图标",
            "settings.onboarding": "引导",
            "settings.firstLaunchOnboarding": "首次启动引导",
            "settings.reopen": "重新打开",
            "settings.generalFootnote": "开启 Dock 隐藏后，关闭主窗口时应用会留在菜单栏；首次引导可随时重新打开。",
            "settings.globalShortcuts": "全局快捷键",
            "settings.history": "历史",
            "settings.persistClipboardHistory": "重启后保留剪贴板历史",
            "settings.normalHistoryLimit": "普通历史上限",
            "settings.clipHistoryFootnote": "关闭保留历史后，已保存的剪贴板历史文件会被删除。",
            "settings.persistScreenshotHistory": "重启后保留截图历史",
            "settings.screenshotHistoryLimit": "截图历史上限",
            "settings.pixHistoryFootnote": "截图可能包含敏感信息；开启保留历史后，会把最近截图保存到本机应用支持目录。",
            "settings.defaultLanguages": "默认语言",
            "settings.defaultSourceLanguage": "默认原文语言",
            "settings.defaultTargetLanguage": "默认目标语言",
            "settings.translationServices": "翻译服务",
            "settings.speechServices": "发音服务",
            "settings.defaultSpeech": "默认发音",
            "settings.persistTranslationHistory": "重启后保留翻译历史",
            "settings.translationHistoryLimit": "翻译历史上限",
            "settings.tranFootnote": "目标语言默认跟随系统；发音默认使用系统语音；翻译历史会保存到本机。",
            "settings.updates": "更新",
            "settings.currentVersion": "当前版本",
            "settings.autoCheckUpdates": "自动检查更新",
            "settings.autoDownloadUpdates": "自动下载更新",
            "settings.checkFrequency": "检查频率",
            "settings.lastChecked": "上次检查",
            "settings.checkUpdates": "检查更新",
            "settings.unknown": "未知",
            "settings.neverChecked": "从未检查",

            "shortcut.mainWindow": "打开主窗口",
            "shortcut.clipboardPanel": "剪贴板快速面板",
            "shortcut.pixCapture": "Pix 捕获",
            "shortcut.translateSelection": "翻译选中文本",
            "shortcut.record": "设置快捷键",
            "shortcut.press": "按下快捷键",

            "common.cancel": "取消",
            "common.delete": "删除",
            "common.copy": "复制",
            "common.save": "保存",
            "common.preview": "预览",
            "common.done": "完成",
            "common.export": "导出",
            "common.clearHistory": "清空历史",
            "common.empty": "空",
            "common.search.clear": "清除搜索",
            "common.openSystemSettings": "打开系统设置",
            "common.records.count": "%d 条记录",
            "common.items.count": "%d 项记录",
            "common.records.filteredCount": "%d/%d 条记录",
            "common.fileItems.more": "%@ 等 %d 个项目",
            "common.favorite": "收藏",
            "common.unfavorite": "取消收藏",
            "common.copyPlainText": "复制纯文本",
            "common.translate": "翻译",
            "common.revealInFinder": "在访达中显示",
            "common.pinToScreen": "固定到屏幕",
            "common.exportMP4": "导出 MP4",
            "common.exportGIF": "导出 GIF",
            "common.zoomOut": "缩小",
            "common.zoomIn": "放大",
            "common.fitWindow": "适应窗口",
            "common.copyImage": "复制图片",
            "common.saveImage": "保存图片",
            "common.cannotPreviewImage": "无法预览图片",
            "common.close": "关闭",
            "common.select": "选择",
            "common.plainText": "纯文本",
            "common.deleteRecord": "删除记录",
            "common.pinWindow": "固定小窗",
            "common.unpinWindow": "取消固定",
            "common.previous": "上一步",
            "common.next": "下一步",
            "common.later": "稍后",
            "common.ok": "好",
            "kind.text": "文本",
            "kind.image": "图片",
            "kind.file": "文件",
            "clip.clearTitle": "清空剪贴板历史？",
            "clip.clearMessage": "这会删除全部剪贴板历史记录，无法撤销。",
            "clip.search": "搜索剪贴板历史",
            "clip.history": "剪贴板历史",
            "clip.empty": "暂无剪贴板记录",
            "clip.noResults": "没有匹配记录",
            "clip.selectItem": "选择一条记录",
            "clip.clearHelp": "清空剪贴板历史",
            "clip.openFull": "打开完整剪贴板",
            "clip.paste": "粘贴",
            "clip.copyBack": "复制回剪贴板",
            "clip.sendToTran": "发送到 Tran",
            "clip.lastCopied": "最近复制",
            "clip.characterCount": "字符数",
            "clip.formatCount": "格式数",
            "clip.itemCount": "项目数",
            "clip.textPreview": "文本预览",
            "clip.richText": "带格式文本",
            "clip.keepsFormatting": "保留格式",
            "clip.textSummary": "文本 · %d 个字符",
            "clip.richTextSummary": "带格式文本 · %d 个字符 · %d 种格式",
            "clip.previewableImage": "图片 · 可预览",
            "clip.pathSummary": "%@ · %@ 等 %d 项",

            "relative.justNow": "刚刚",
            "relative.minutesAgo": "%d分钟前",
            "relative.hoursAgo": "%d小时前",
            "relative.daysAgo": "%d天前",
            "pix.clearTitle": "清空 Pix 历史？",
            "pix.clearMessage": "这会删除全部截图和录屏历史记录，无法撤销。",
            "pix.search": "搜索 Pix 历史",
            "pix.history": "Pix 历史",
            "pix.empty": "暂无截图",
            "pix.noResults": "没有匹配 Pix 记录",
            "pix.clearHelp": "清空截图历史",
            "pix.pngImage": "PNG 图片",
            "pix.mp4Recording": "MP4 录屏",
            "pix.recording": "录屏",
            "pix.fullScreen": "全屏",
            "pix.screenshot": "截图",
            "pix.captureSelected": "截图",
            "pix.captureSelected.help": "拖拽选择屏幕区域截图",
            "pix.recordSelected": "录屏",
            "pix.recordSelected.help": "拖拽选择屏幕区域并开始录屏",
            "pix.captureFullScreen.help": "捕获主屏幕画面",
            "pix.cancelSelection": "取消框选",
            "pix.cancelSelection.help": "结束当前框选",
            "pix.saving": "正在保存",
            "pix.stopRecording": "停止录屏",
            "pix.stopRecording.help": "停止并保存当前录屏",
            "pix.copyScreenshot": "复制截图",
            "pix.saveScreenshot": "保存截图",
            "pix.openInPreview": "用系统预览.app打开截图",
            "pix.openRecording": "打开录屏",
            "pix.deleteScreenshot": "删除截图",
            "pix.imagePreview": "图片预览",
            "pix.recordingPreview": "录屏预览",
            "pix.details": "详情",
            "pix.type": "类型",
            "pix.createdAt": "创建时间",
            "pix.fileSize": "文件大小",
            "pix.duration": "时长",
            "pix.dimensions": "尺寸",
            "pix.ocr.section": "识别文本",
            "pix.ocr.extract": "提取文字",
            "pix.ocr.extract.help": "识别这张截图中的文字",
            "pix.ocr.recognizing": "识别中…",
            "pix.ocr.empty": "尚未识别文字。提取截图文字后可复制、翻译，或日后通过搜索找到这张截图。",
            "pix.ocr.noText": "这张截图中没有找到文字。",
            "pix.ocr.recognizeAgain": "重新提取",
            "pix.ocr.recognizeAgain.help": "重新进行文字识别",
            "pix.ocr.save": "保存",
            "pix.ocr.translate": "翻译",
            "pix.ocr.copyText": "复制文字",
            "pix.ocr.tool": "识别文字",
            "pix.ocr.tool.help": "识别所选区域的文字并复制",
            "pix.ocr.invalidImage": "无法读取这张图片。",
            "pix.ocr.noTextRecognized": "未识别到文字。",
            "pix.ocr.recognizedCopied": "已识别并复制文字。",
            "gif.exportTitle": "导出 GIF",
            "gif.frameCount": "%d 帧",
            "gif.previewFrameCount": "%d 帧预览",
            "gif.truncatedPreview": "%d 帧 · 前 %@",
            "gif.frameRate": "帧率",
            "gif.speed": "速度",
            "gif.maxDimension": "最大边长",
            "gif.maxFrames": "最大帧数",
            "gif.frameUnit": "帧",
            "capture.mode": "捕获模式",
            "capture.tool.move": "移动",
            "capture.tool.rectangle": "矩形",
            "capture.tool.ellipse": "椭圆",
            "capture.tool.arrow": "箭头",
            "capture.tool.pen": "画笔",
            "capture.tool.text": "文字",
            "capture.tool.mosaic": "马赛克",
            "capture.undo": "撤销",
            "capture.redo": "重做",
            "capture.startRecording": "开始录制",
            "capture.mosaicMode": "马赛克模式",
            "capture.mosaicBlockSize": "模糊块大小",
            "capture.mosaicBrushSize": "涂抹范围",
            "capture.color": "颜色",
            "capture.lineWidth": "线条粗细",
            "capture.fontSize": "字号大小",
            "language.autoDetect": "自动识别",
            "language.zhHans": "简体中文",
            "language.zhHant": "繁体中文",
            "language.english": "英语",
            "language.japanese": "日语",
            "language.korean": "韩语",
            "language.french": "法语",
            "language.german": "德语",
            "tran.clearTitle": "清空翻译历史？",
            "tran.clearMessage": "这会删除全部翻译历史记录，无法撤销。",
            "tran.textTranslation": "文本翻译",
            "tran.translate": "翻译",
            "tran.sourceText": "原文",
            "tran.speakSource": "朗读原文",
            "tran.result": "翻译结果",
            "tran.providerCount": "%d 个服务",
            "tran.sourceLanguage": "原文语言",
            "tran.targetLanguage": "目标语言",
            "tran.swapLanguages": "交换语言",
            "tran.autoDetectedLanguage": "自动识别：%@",
            "tran.emptyHistory": "还没有翻译记录",
            "tran.searchHistory": "搜索翻译历史",
            "tran.noResults": "没有匹配翻译",
            "tran.history": "翻译历史",
            "tran.clearHelp": "清空翻译历史",
            "tran.loadHistory": "载入这条翻译",
            "tran.deleteHistory": "删除翻译记录",
            "tran.switchProvider": "切换到 %@ 的结果",
            "tran.localProvider": "本地",
            "tran.retry": "重新翻译",
            "tran.speakTranslation": "朗读译文",
            "tran.stopSpeaking": "停止朗读",
            "tran.copyTranslation": "复制译文",
            "tran.inputSource": "输入原文",
            "tran.readingSelection": "正在读取选中文本...",
            "tran.selectionTranslation": "划词翻译",
            "tran.copySource": "复制原文",
            "tran.openFull": "打开完整翻译",
            "tran.expandQuickPanel": "展开小窗",
            "tran.collapseQuickPanel": "收起小窗",
            "tran.changeSourceLanguage": "切换原文语言",
            "tran.changeTargetLanguage": "切换目标语言",
            "tran.characterCount": "%d 字",
            "tran.quickPanelShortcut": "Enter 翻译 / ⌘↩ 换行",
            "tran.retranslateCurrentSource": "用当前原文重新翻译",
            "tran.noProviders": "暂无翻译服务",
            "tran.detectedSummary": "检测：%@ · %@",
            "tran.defaultIdleMessage": "输入文本后点击翻译，结果会显示在这里。",
            "tran.historyIdleMessage": "载入历史记录后，可点击翻译刷新其它 provider。",
            "tran.disabledProviderMessage": "此 provider 已在设置中关闭。",
            "tran.translating": "正在翻译...",
            "tran.speechFailed": "发音失败：%@",
            "tran.emptySourceError": "请输入要翻译的文本。",
            "tran.providerUnavailable": "当前翻译服务不可用。请稍后重试，或检查系统翻译语言包。",
            "tran.providerNoneEnabled": "请至少启用一个翻译 provider。",
            "speech.providerUnavailable": "当前发音服务不可用。请稍后重试，或检查发音 provider 配置。",
            "speech.requestFailed": "发音服务请求失败（HTTP %d）。",
            "textSelection.noSelection": "没有检测到选中文本。",
            "clipboard.writeFailed": "无法写入剪贴板。",
            "screenshot.permissionDenied": "无法读取屏幕内容。请在系统设置中允许 %@ 录制屏幕，授权后重启应用再试。",
            "screenshot.missingEntitlements": "当前构建缺少屏幕录制所需权限配置。",
            "screenshot.displayNotFound": "无法定位要截图的显示器。",
            "screenshot.timedOut": "截图响应超时，请重试。",
            "screenshot.unavailable": "无法获取当前屏幕截图。",
            "screenshot.pngEncodingFailed": "截图已生成，但无法转换为 PNG。",
            "screenshot.invalidImageData": "无法识别这张截图。",
            "screenshot.missingDestination": "未选择保存位置。",
            "screenshot.pinFailed": "无法固定这张截图。",
            "screenshot.closePinned": "关闭固定截图",
            "recording.missingFile": "找不到录屏文件。",
            "recording.outputRejected": "无法创建录屏输出。",
            "recording.didNotFinish": "录屏文件写入超时，请重试。",
            "recording.gifDestinationFailed": "无法创建 GIF 文件。",
            "recording.gifFrameGenerationFailed": "无法从录屏中生成 GIF 帧。",
            "recording.cancel": "取消录屏",
            "launchAtLogin.disabledMessage": "关闭后，此应用不会随系统登录自动启动。",
            "launchAtLogin.enabledMessage": "已开启，系统登录后会自动启动此应用。",
            "launchAtLogin.requiresApprovalMessage": "已请求开机启动，请在系统设置的登录项中允许此应用。",
            "launchAtLogin.unavailableMessage": "当前构建无法注册为登录项。",
            "launchAtLogin.updateFailed": "无法更新开机启动设置：%@",
            "onboarding.windowTitle": "准备使用",
            "onboarding.ready": "准备使用",
            "onboarding.skipNote": "你可以跳过引导，之后从设置里重新打开。",
            "onboarding.screenRecordingExplanation": "Pix 需要读取屏幕内容来完成截图、区域选择和录屏。",
            "onboarding.accessibilityExplanation": "Tran 需要辅助功能权限读取选中文本，Pix 也会用它识别窗口和控件位置。",
            "onboarding.shortcutsExplanation": "确认常用全局快捷键。这里和设置页使用同一套配置，之后也可以随时修改。",
            "onboarding.authorizeScreenRecording": "授权屏幕录制",
            "onboarding.recheck": "重新检测",
            "onboarding.skip": "跳过引导",
            "onboarding.screenRecordingAuthorizedMessage": "屏幕录制权限已授权。",
            "onboarding.screenRecordingPromptFallbackOpenedSettings": "系统没有弹出授权提示。已为你打开系统设置，请允许 %@ 录制屏幕后重新检测。",
            "onboarding.screenRecordingPromptFallbackManual": "系统没有弹出授权提示。请手动前往隐私与安全性中的屏幕录制，允许 %@ 后重新检测。",
            "onboarding.settingsOpenedRecheck": "系统设置已打开。授权后回到这里点击重新检测。",
            "onboarding.accessibilitySettingsOpened": "系统设置已打开。打开 %@ 后回到这里点击重新检测。",
            "onboarding.screenRecordingSettingsOpenFailed": "无法打开系统设置，请手动前往隐私与安全性中的屏幕录制。",
            "onboarding.accessibilitySettingsOpenFailed": "无法打开系统设置，请手动前往隐私与安全性中的辅助功能。",
            "onboarding.screenRecordingTitle": "允许屏幕录制",
            "onboarding.accessibilityTitle": "允许辅助功能",
            "onboarding.shortcutsTitle": "确认全局快捷键",
            "onboarding.screenRecordingSubtitle": "用于 Pix 截图、区域选择和录屏",
            "onboarding.accessibilitySubtitle": "用于读取选中文本和识别窗口控件",
            "onboarding.shortcutsSubtitle": "让常用操作可以随手唤起",
            "onboarding.adjustable": "可调整",
            "onboarding.authorized": "已授权",
            "onboarding.notAuthorized": "未授权",
            "onboarding.capabilityReady": "这项能力已经准备好。",
            "onboarding.capabilityNeedsPermission": "授权后功能体验会更完整。",
            "update.checkingProgress": "正在检查更新...",
            "update.downloadingProgress": "正在下载更新...",
            "update.extractingProgress": "正在准备更新...",
            "update.readyToInstallMessage": "更新已准备好。安装完成后应用会重新启动。",
            "update.installingProgress": "正在安装更新...",
            "update.installedMessage": "更新已安装完成。",
            "update.alreadyLatestMessage": "应用已经是最新版本。",
            "update.checkFailedMessage": "无法完成更新检查。",
            "update.skipVersion": "跳过此版本",
            "update.releaseNotes": "更新内容",
            "update.titleAlreadyLatest": "已是最新版本",
            "update.titleFailed": "更新失败",
            "update.titleReadyToInstall": "可以安装了",
            "update.titleInstalling": "正在安装更新...",
            "update.titleInstalled": "更新已安装",
            "update.windowTitle": "更新",
            "update.availableTitle": "%@ 可用",
            "update.versionSubtitle": "当前 %@ -> 最新 %@",
            "update.installAndRelaunch": "安装并重启",
            "update.install": "安装更新",
            "update.downloadedMessage": "更新已下载完成。",
            "update.unavailableDebugBuild": "Debug 构建不会检查更新；请使用 Release 构建测试更新。",
            "update.availableStatus": "当前构建可使用自动更新。",
            "update.unavailableConfiguration": "当前构建未配置自动更新。",
            "update.unavailableAlertTitle": "自动更新未配置",
            "update.unavailableAlertMessage": "当前构建缺少检查更新所需配置。",
            "update.frequency.daily": "每天",
            "update.frequency.weekly": "每周",
            "update.frequency.monthly": "每月",
        ]
    ]
}

extension L10n {
    static var appName: String { tr("app.name", "ClipPixTran") }
    static var appSettings: String { tr("app.settings", "设置") }
    static var appOpenSettings: String { tr("app.openSettings", "打开设置") }
    static var appDebugBuild: String { tr("app.debugBuild", "Debug 构建") }
    static var appDebugBuildTitle: String { tr("app.debugBuild.title", "Debug 构建") }
    static var appQuit: String { tr("app.quit", "退出") }
    static var appReopenOnboarding: String { tr("app.reopenOnboarding", "重新打开引导") }

    static var languageHeader: String { tr("language.header", "语言") }
    static var languageSystem: String { tr("language.system", "跟随系统") }
    static var settingsGeneral: String { tr("settings.general", "通用") }
    static var settingsShortcuts: String { tr("settings.shortcuts", "快捷键") }
    static var settingsAbout: String { tr("settings.about", "关于") }
    static var settingsStartup: String { tr("settings.startup", "启动") }
    static var settingsLaunchAtLogin: String { tr("settings.launchAtLogin", "开机时启动") }
    static var settingsDock: String { tr("settings.dock", "Dock") }
    static var settingsInterfaceLanguage: String { tr("settings.interfaceLanguage", "界面语言") }
    static var settingsHideDockIcon: String { tr("settings.hideDockIcon", "关闭主窗口后隐藏 Dock 图标") }
    static var settingsOnboarding: String { tr("settings.onboarding", "引导") }
    static var settingsFirstLaunchOnboarding: String { tr("settings.firstLaunchOnboarding", "首次启动引导") }
    static var settingsReopen: String { tr("settings.reopen", "重新打开") }
    static var settingsGeneralFootnote: String { tr("settings.generalFootnote", "开启 Dock 隐藏后，关闭主窗口时应用会留在菜单栏；首次引导可随时重新打开。") }
    static var settingsGlobalShortcuts: String { tr("settings.globalShortcuts", "全局快捷键") }
    static var settingsHistory: String { tr("settings.history", "历史") }
    static var settingsPersistClipboardHistory: String { tr("settings.persistClipboardHistory", "重启后保留剪贴板历史") }
    static var settingsNormalHistoryLimit: String { tr("settings.normalHistoryLimit", "普通历史上限") }
    static var settingsClipHistoryFootnote: String { tr("settings.clipHistoryFootnote", "关闭保留历史后，已保存的剪贴板历史文件会被删除。") }
    static var settingsPersistScreenshotHistory: String { tr("settings.persistScreenshotHistory", "重启后保留截图历史") }
    static var settingsScreenshotHistoryLimit: String { tr("settings.screenshotHistoryLimit", "截图历史上限") }
    static var settingsPixHistoryFootnote: String { tr("settings.pixHistoryFootnote", "截图可能包含敏感信息；开启保留历史后，会把最近截图保存到本机应用支持目录。") }
    static var settingsDefaultLanguages: String { tr("settings.defaultLanguages", "默认语言") }
    static var settingsDefaultSourceLanguage: String { tr("settings.defaultSourceLanguage", "默认原文语言") }
    static var settingsDefaultTargetLanguage: String { tr("settings.defaultTargetLanguage", "默认目标语言") }
    static var settingsTranslationServices: String { tr("settings.translationServices", "翻译服务") }
    static var settingsSpeechServices: String { tr("settings.speechServices", "发音服务") }
    static var settingsDefaultSpeech: String { tr("settings.defaultSpeech", "默认发音") }
    static var settingsPersistTranslationHistory: String { tr("settings.persistTranslationHistory", "重启后保留翻译历史") }
    static var settingsTranslationHistoryLimit: String { tr("settings.translationHistoryLimit", "翻译历史上限") }
    static var settingsTranFootnote: String { tr("settings.tranFootnote", "目标语言默认跟随系统；发音默认使用系统语音；翻译历史会保存到本机。") }
    static var settingsUpdates: String { tr("settings.updates", "更新") }
    static var settingsCurrentVersion: String { tr("settings.currentVersion", "当前版本") }
    static var settingsAutoCheckUpdates: String { tr("settings.autoCheckUpdates", "自动检查更新") }
    static var settingsAutoDownloadUpdates: String { tr("settings.autoDownloadUpdates", "自动下载更新") }
    static var settingsCheckFrequency: String { tr("settings.checkFrequency", "检查频率") }
    static var settingsLastChecked: String { tr("settings.lastChecked", "上次检查") }
    static var settingsCheckUpdates: String { tr("settings.checkUpdates", "检查更新") }
    static var settingsUnknown: String { tr("settings.unknown", "未知") }
    static var settingsNeverChecked: String { tr("settings.neverChecked", "从未检查") }

    static var shortcutMainWindow: String { tr("shortcut.mainWindow", "打开主窗口") }
    static var shortcutClipboardPanel: String { tr("shortcut.clipboardPanel", "剪贴板快速面板") }
    static var shortcutPixCapture: String { tr("shortcut.pixCapture", "Pix 捕获") }
    static var shortcutTranslateSelection: String { tr("shortcut.translateSelection", "翻译选中文本") }
    static var shortcutRecord: String { tr("shortcut.record", "设置快捷键") }
    static var shortcutPress: String { tr("shortcut.press", "按下快捷键") }

    static var commonCancel: String { tr("common.cancel", "取消") }
    static var commonDelete: String { tr("common.delete", "删除") }
    static var commonCopy: String { tr("common.copy", "复制") }
    static var commonSave: String { tr("common.save", "保存") }
    static var commonPreview: String { tr("common.preview", "预览") }
    static var commonDone: String { tr("common.done", "完成") }
    static var commonExport: String { tr("common.export", "导出") }
    static var commonClearHistory: String { tr("common.clearHistory", "清空历史") }
    static var commonSearchClear: String { tr("common.search.clear", "清除搜索") }
    static var commonOpenSystemSettings: String { tr("common.openSystemSettings", "打开系统设置") }
    static func commonRecordsCount(_ count: Int) -> String { format("common.records.count", "%d 条记录", count) }
    static func commonItemsCount(_ count: Int) -> String { format("common.items.count", "%d 项记录", count) }
    static func commonFilteredRecordsCount(visible: Int, total: Int) -> String {
        format("common.records.filteredCount", "%d/%d 条记录", visible, total)
    }
    static func commonFileItemsMore(name: String, count: Int) -> String {
        format("common.fileItems.more", "%@ 等 %d 个项目", name, count)
    }
    static var commonFavorite: String { tr("common.favorite", "收藏") }
    static var commonUnfavorite: String { tr("common.unfavorite", "取消收藏") }
    static var commonCopyPlainText: String { tr("common.copyPlainText", "复制纯文本") }
    static var commonTranslate: String { tr("common.translate", "翻译") }
    static var commonRevealInFinder: String { tr("common.revealInFinder", "在访达中显示") }
    static var commonPinToScreen: String { tr("common.pinToScreen", "固定到屏幕") }
    static var commonExportMP4: String { tr("common.exportMP4", "导出 MP4") }
    static var commonExportGIF: String { tr("common.exportGIF", "导出 GIF") }
    static var commonZoomOut: String { tr("common.zoomOut", "缩小") }
    static var commonZoomIn: String { tr("common.zoomIn", "放大") }
    static var commonFitWindow: String { tr("common.fitWindow", "适应窗口") }
    static var commonCopyImage: String { tr("common.copyImage", "复制图片") }
    static var commonSaveImage: String { tr("common.saveImage", "保存图片") }
    static var commonCannotPreviewImage: String { tr("common.cannotPreviewImage", "无法预览图片") }
    static var commonClose: String { tr("common.close", "关闭") }
    static var commonSelect: String { tr("common.select", "选择") }
    static var commonPlainText: String { tr("common.plainText", "纯文本") }
    static var commonDeleteRecord: String { tr("common.deleteRecord", "删除记录") }
    static var commonPinWindow: String { tr("common.pinWindow", "固定小窗") }
    static var commonUnpinWindow: String { tr("common.unpinWindow", "取消固定") }
    static var commonPrevious: String { tr("common.previous", "上一步") }
    static var commonNext: String { tr("common.next", "下一步") }
    static var commonLater: String { tr("common.later", "稍后") }
    static var commonOK: String { tr("common.ok", "好") }
    static var kindText: String { tr("kind.text", "文本") }
    static var kindImage: String { tr("kind.image", "图片") }
    static var kindFile: String { tr("kind.file", "文件") }
    static var clipClearTitle: String { tr("clip.clearTitle", "清空剪贴板历史？") }
    static var clipClearMessage: String { tr("clip.clearMessage", "这会删除全部剪贴板历史记录，无法撤销。") }
    static var clipSearch: String { tr("clip.search", "搜索剪贴板历史") }
    static var clipHistory: String { tr("clip.history", "剪贴板历史") }
    static var clipEmpty: String { tr("clip.empty", "暂无剪贴板记录") }
    static var clipNoResults: String { tr("clip.noResults", "没有匹配记录") }
    static var clipSelectItem: String { tr("clip.selectItem", "选择一条记录") }
    static var clipClearHelp: String { tr("clip.clearHelp", "清空剪贴板历史") }
    static var clipOpenFull: String { tr("clip.openFull", "打开完整剪贴板") }
    static var clipPaste: String { tr("clip.paste", "粘贴") }
    static var clipCopyBack: String { tr("clip.copyBack", "复制回剪贴板") }
    static var clipSendToTran: String { tr("clip.sendToTran", "发送到 Tran") }
    static var clipLastCopied: String { tr("clip.lastCopied", "最近复制") }
    static var clipCharacterCount: String { tr("clip.characterCount", "字符数") }
    static var clipFormatCount: String { tr("clip.formatCount", "格式数") }
    static var clipItemCount: String { tr("clip.itemCount", "项目数") }
    static var clipTextPreview: String { tr("clip.textPreview", "文本预览") }
    static var clipRichText: String { tr("clip.richText", "带格式文本") }
    static var clipKeepsFormatting: String { tr("clip.keepsFormatting", "保留格式") }
    static func clipTextSummary(characterCount: Int) -> String {
        format("clip.textSummary", "文本 · %d 个字符", characterCount)
    }
    static func clipRichTextSummary(characterCount: Int, formatCount: Int) -> String {
        format("clip.richTextSummary", "带格式文本 · %d 个字符 · %d 种格式", characterCount, formatCount)
    }
    static var clipPreviewableImage: String { tr("clip.previewableImage", "图片 · 可预览") }
    static func clipPathSummary(prefix: String, name: String, count: Int) -> String {
        format("clip.pathSummary", "%@ · %@ 等 %d 项", prefix, name, count)
    }

    static var relativeJustNow: String { tr("relative.justNow", "刚刚") }
    static func relativeMinutesAgo(_ minutes: Int) -> String { format("relative.minutesAgo", "%d分钟前", minutes) }
    static func relativeHoursAgo(_ hours: Int) -> String { format("relative.hoursAgo", "%d小时前", hours) }
    static func relativeDaysAgo(_ days: Int) -> String { format("relative.daysAgo", "%d天前", days) }
    static var pixClearTitle: String { tr("pix.clearTitle", "清空 Pix 历史？") }
    static var pixClearMessage: String { tr("pix.clearMessage", "这会删除全部截图和录屏历史记录，无法撤销。") }
    static var pixSearch: String { tr("pix.search", "搜索 Pix 历史") }
    static var pixHistory: String { tr("pix.history", "Pix 历史") }
    static var pixEmpty: String { tr("pix.empty", "暂无截图") }
    static var pixNoResults: String { tr("pix.noResults", "没有匹配 Pix 记录") }
    static var pixClearHelp: String { tr("pix.clearHelp", "清空截图历史") }
    static var pixPNGImage: String { tr("pix.pngImage", "PNG 图片") }
    static var pixMP4Recording: String { tr("pix.mp4Recording", "MP4 录屏") }
    static var pixRecording: String { tr("pix.recording", "录屏") }
    static var pixFullScreen: String { tr("pix.fullScreen", "全屏") }
    static var pixScreenshot: String { tr("pix.screenshot", "截图") }
    static var pixCaptureSelected: String { tr("pix.captureSelected", "截图") }
    static var pixCaptureSelectedHelp: String { tr("pix.captureSelected.help", "拖拽选择屏幕区域截图") }
    static var pixRecordSelected: String { tr("pix.recordSelected", "录屏") }
    static var pixRecordSelectedHelp: String { tr("pix.recordSelected.help", "拖拽选择屏幕区域并开始录屏") }
    static var pixCaptureFullScreenHelp: String { tr("pix.captureFullScreen.help", "捕获主屏幕画面") }
    static var pixCancelSelection: String { tr("pix.cancelSelection", "取消框选") }
    static var pixCancelSelectionHelp: String { tr("pix.cancelSelection.help", "结束当前框选") }
    static var pixSaving: String { tr("pix.saving", "正在保存") }
    static var pixStopRecording: String { tr("pix.stopRecording", "停止录屏") }
    static var pixStopRecordingHelp: String { tr("pix.stopRecording.help", "停止并保存当前录屏") }
    static var pixCopyScreenshot: String { tr("pix.copyScreenshot", "复制截图") }
    static var pixSaveScreenshot: String { tr("pix.saveScreenshot", "保存截图") }
    static var pixOpenInPreview: String { tr("pix.openInPreview", "用系统预览.app打开截图") }
    static var pixOpenRecording: String { tr("pix.openRecording", "打开录屏") }
    static var pixDeleteScreenshot: String { tr("pix.deleteScreenshot", "删除截图") }
    static var pixImagePreview: String { tr("pix.imagePreview", "图片预览") }
    static var pixRecordingPreview: String { tr("pix.recordingPreview", "录屏预览") }
    static var pixDetails: String { tr("pix.details", "详情") }
    static var pixType: String { tr("pix.type", "类型") }
    static var pixCreatedAt: String { tr("pix.createdAt", "创建时间") }
    static var pixFileSize: String { tr("pix.fileSize", "文件大小") }
    static var pixDuration: String { tr("pix.duration", "时长") }
    static var pixDimensions: String { tr("pix.dimensions", "尺寸") }
    static var pixOCRSection: String { tr("pix.ocr.section", "识别文本") }
    static var pixOCRExtract: String { tr("pix.ocr.extract", "提取文字") }
    static var pixOCRExtractHelp: String { tr("pix.ocr.extract.help", "识别这张截图中的文字") }
    static var pixOCRRecognizing: String { tr("pix.ocr.recognizing", "识别中…") }
    static var pixOCREmpty: String { tr("pix.ocr.empty", "尚未识别文字。提取截图文字后可复制、翻译，或日后通过搜索找到这张截图。") }
    static var pixOCRNoText: String { tr("pix.ocr.noText", "这张截图中没有找到文字。") }
    static var pixOCRRecognizeAgain: String { tr("pix.ocr.recognizeAgain", "重新提取") }
    static var pixOCRRecognizeAgainHelp: String { tr("pix.ocr.recognizeAgain.help", "重新进行文字识别") }
    static var pixOCRSave: String { tr("pix.ocr.save", "保存") }
    static var pixOCRTranslate: String { tr("pix.ocr.translate", "翻译") }
    static var pixOCRCopyText: String { tr("pix.ocr.copyText", "复制文字") }
    static var pixOCRTool: String { tr("pix.ocr.tool", "识别文字") }
    static var pixOCRToolHelp: String { tr("pix.ocr.tool.help", "识别所选区域的文字并复制") }
    static var pixOCRInvalidImage: String { tr("pix.ocr.invalidImage", "无法读取这张图片。") }
    static var pixOCRNoTextRecognized: String { tr("pix.ocr.noTextRecognized", "未识别到文字。") }
    static var pixOCRRecognizedCopied: String { tr("pix.ocr.recognizedCopied", "已识别并复制文字。") }
    static var gifExportTitle: String { tr("gif.exportTitle", "导出 GIF") }
    static func gifFrameCount(_ count: Int) -> String { format("gif.frameCount", "%d 帧", count) }
    static func gifPreviewFrameCount(_ count: Int) -> String { format("gif.previewFrameCount", "%d 帧预览", count) }
    static func gifTruncatedPreview(frameCount: Int, duration: String) -> String {
        format("gif.truncatedPreview", "%d 帧 · 前 %@", frameCount, duration)
    }
    static var gifFrameRate: String { tr("gif.frameRate", "帧率") }
    static var gifSpeed: String { tr("gif.speed", "速度") }
    static var gifMaxDimension: String { tr("gif.maxDimension", "最大边长") }
    static var gifMaxFrames: String { tr("gif.maxFrames", "最大帧数") }
    static var gifFrameUnit: String { tr("gif.frameUnit", "帧") }
    static var captureMode: String { tr("capture.mode", "捕获模式") }
    static var captureToolMove: String { tr("capture.tool.move", "移动") }
    static var captureToolRectangle: String { tr("capture.tool.rectangle", "矩形") }
    static var captureToolEllipse: String { tr("capture.tool.ellipse", "椭圆") }
    static var captureToolArrow: String { tr("capture.tool.arrow", "箭头") }
    static var captureToolPen: String { tr("capture.tool.pen", "画笔") }
    static var captureToolText: String { tr("capture.tool.text", "文字") }
    static var captureToolMosaic: String { tr("capture.tool.mosaic", "马赛克") }
    static var captureUndo: String { tr("capture.undo", "撤销") }
    static var captureRedo: String { tr("capture.redo", "重做") }
    static var captureStartRecording: String { tr("capture.startRecording", "开始录制") }
    static var captureMosaicMode: String { tr("capture.mosaicMode", "马赛克模式") }
    static var captureMosaicBlockSize: String { tr("capture.mosaicBlockSize", "模糊块大小") }
    static var captureMosaicBrushSize: String { tr("capture.mosaicBrushSize", "涂抹范围") }
    static var captureColor: String { tr("capture.color", "颜色") }
    static var captureLineWidth: String { tr("capture.lineWidth", "线条粗细") }
    static var captureFontSize: String { tr("capture.fontSize", "字号大小") }
    static var languageAutoDetect: String { tr("language.autoDetect", "自动识别") }
    static var languageZhHans: String { tr("language.zhHans", "简体中文") }
    static var languageZhHant: String { tr("language.zhHant", "繁体中文") }
    static var languageEnglish: String { tr("language.english", "英语") }
    static var languageJapanese: String { tr("language.japanese", "日语") }
    static var languageKorean: String { tr("language.korean", "韩语") }
    static var languageFrench: String { tr("language.french", "法语") }
    static var languageGerman: String { tr("language.german", "德语") }
    static var tranClearTitle: String { tr("tran.clearTitle", "清空翻译历史？") }
    static var tranClearMessage: String { tr("tran.clearMessage", "这会删除全部翻译历史记录，无法撤销。") }
    static var tranTextTranslation: String { tr("tran.textTranslation", "文本翻译") }
    static var tranTranslate: String { tr("tran.translate", "翻译") }
    static var tranSourceText: String { tr("tran.sourceText", "原文") }
    static var tranSpeakSource: String { tr("tran.speakSource", "朗读原文") }
    static var tranResult: String { tr("tran.result", "翻译结果") }
    static func tranProviderCount(_ count: Int) -> String { format("tran.providerCount", "%d 个服务", count) }
    static var tranSourceLanguage: String { tr("tran.sourceLanguage", "原文语言") }
    static var tranTargetLanguage: String { tr("tran.targetLanguage", "目标语言") }
    static var tranSwapLanguages: String { tr("tran.swapLanguages", "交换语言") }
    static func tranAutoDetectedLanguage(_ language: String) -> String {
        format("tran.autoDetectedLanguage", "自动识别：%@", language)
    }
    static var tranEmptyHistory: String { tr("tran.emptyHistory", "还没有翻译记录") }
    static var tranSearchHistory: String { tr("tran.searchHistory", "搜索翻译历史") }
    static var tranNoResults: String { tr("tran.noResults", "没有匹配翻译") }
    static var tranHistory: String { tr("tran.history", "翻译历史") }
    static var tranClearHelp: String { tr("tran.clearHelp", "清空翻译历史") }
    static var tranLoadHistory: String { tr("tran.loadHistory", "载入这条翻译") }
    static var tranDeleteHistory: String { tr("tran.deleteHistory", "删除翻译记录") }
    static func tranSwitchProvider(_ providerName: String) -> String {
        format("tran.switchProvider", "切换到 %@ 的结果", providerName)
    }
    static var tranLocalProvider: String { tr("tran.localProvider", "本地") }
    static var tranRetry: String { tr("tran.retry", "重新翻译") }
    static var tranSpeakTranslation: String { tr("tran.speakTranslation", "朗读译文") }
    static var tranStopSpeaking: String { tr("tran.stopSpeaking", "停止朗读") }
    static var tranCopyTranslation: String { tr("tran.copyTranslation", "复制译文") }
    static var tranInputSource: String { tr("tran.inputSource", "输入原文") }
    static var tranReadingSelection: String { tr("tran.readingSelection", "正在读取选中文本...") }
    static var tranSelectionTranslation: String { tr("tran.selectionTranslation", "划词翻译") }
    static var tranCopySource: String { tr("tran.copySource", "复制原文") }
    static var tranOpenFull: String { tr("tran.openFull", "打开完整翻译") }
    static var tranExpandQuickPanel: String { tr("tran.expandQuickPanel", "展开小窗") }
    static var tranCollapseQuickPanel: String { tr("tran.collapseQuickPanel", "收起小窗") }
    static var tranChangeSourceLanguage: String { tr("tran.changeSourceLanguage", "切换原文语言") }
    static var tranChangeTargetLanguage: String { tr("tran.changeTargetLanguage", "切换目标语言") }
    static func tranCharacterCount(_ count: Int) -> String {
        format("tran.characterCount", "%d 字", count)
    }
    static var tranQuickPanelShortcut: String { tr("tran.quickPanelShortcut", "Enter 翻译 / ⌘↩ 换行") }
    static var tranRetranslateCurrentSource: String { tr("tran.retranslateCurrentSource", "用当前原文重新翻译") }
    static var tranNoProviders: String { tr("tran.noProviders", "暂无翻译服务") }
    static func tranDetectedSummary(language: String, providerCount: String) -> String {
        format("tran.detectedSummary", "检测：%@ · %@", language, providerCount)
    }
    static var tranDefaultIdleMessage: String { tr("tran.defaultIdleMessage", "输入文本后点击翻译，结果会显示在这里。") }
    static var tranHistoryIdleMessage: String { tr("tran.historyIdleMessage", "载入历史记录后，可点击翻译刷新其它 provider。") }
    static var tranDisabledProviderMessage: String { tr("tran.disabledProviderMessage", "此 provider 已在设置中关闭。") }
    static var tranTranslating: String { tr("tran.translating", "正在翻译...") }
    static func tranSpeechFailed(_ message: String) -> String {
        format("tran.speechFailed", "发音失败：%@", message)
    }
    static var tranEmptySourceError: String { tr("tran.emptySourceError", "请输入要翻译的文本。") }
    static var tranProviderUnavailable: String { tr("tran.providerUnavailable", "当前翻译服务不可用。请稍后重试，或检查系统翻译语言包。") }
    static var tranProviderNoneEnabled: String { tr("tran.providerNoneEnabled", "请至少启用一个翻译 provider。") }
    static var speechProviderUnavailable: String { tr("speech.providerUnavailable", "当前发音服务不可用。请稍后重试，或检查发音 provider 配置。") }
    static func speechRequestFailed(statusCode: Int) -> String {
        format("speech.requestFailed", "发音服务请求失败（HTTP %d）。", statusCode)
    }
    static var textSelectionNoSelection: String { tr("textSelection.noSelection", "没有检测到选中文本。") }
    static var clipboardWriteFailed: String { tr("clipboard.writeFailed", "无法写入剪贴板。") }
    static var screenshotPermissionDenied: String {
        format("screenshot.permissionDenied", "无法读取屏幕内容。请在系统设置中允许 %@ 录制屏幕，授权后重启应用再试。", appName)
    }
    static var screenshotMissingEntitlements: String { tr("screenshot.missingEntitlements", "当前构建缺少屏幕录制所需权限配置。") }
    static var screenshotDisplayNotFound: String { tr("screenshot.displayNotFound", "无法定位要截图的显示器。") }
    static var screenshotTimedOut: String { tr("screenshot.timedOut", "截图响应超时，请重试。") }
    static var screenshotUnavailable: String { tr("screenshot.unavailable", "无法获取当前屏幕截图。") }
    static var screenshotPNGEncodingFailed: String { tr("screenshot.pngEncodingFailed", "截图已生成，但无法转换为 PNG。") }
    static var screenshotInvalidImageData: String { tr("screenshot.invalidImageData", "无法识别这张截图。") }
    static var screenshotMissingDestination: String { tr("screenshot.missingDestination", "未选择保存位置。") }
    static var screenshotPinFailed: String { tr("screenshot.pinFailed", "无法固定这张截图。") }
    static var screenshotClosePinned: String { tr("screenshot.closePinned", "关闭固定截图") }
    static var recordingMissingFile: String { tr("recording.missingFile", "找不到录屏文件。") }
    static var recordingOutputRejected: String { tr("recording.outputRejected", "无法创建录屏输出。") }
    static var recordingDidNotFinish: String { tr("recording.didNotFinish", "录屏文件写入超时，请重试。") }
    static var recordingGIFDestinationFailed: String { tr("recording.gifDestinationFailed", "无法创建 GIF 文件。") }
    static var recordingGIFFrameGenerationFailed: String { tr("recording.gifFrameGenerationFailed", "无法从录屏中生成 GIF 帧。") }
    static var recordingCancel: String { tr("recording.cancel", "取消录屏") }
    static var launchAtLoginDisabledMessage: String { tr("launchAtLogin.disabledMessage", "关闭后，此应用不会随系统登录自动启动。") }
    static var launchAtLoginEnabledMessage: String { tr("launchAtLogin.enabledMessage", "已开启，系统登录后会自动启动此应用。") }
    static var launchAtLoginRequiresApprovalMessage: String { tr("launchAtLogin.requiresApprovalMessage", "已请求开机启动，请在系统设置的登录项中允许此应用。") }
    static var launchAtLoginUnavailableMessage: String { tr("launchAtLogin.unavailableMessage", "当前构建无法注册为登录项。") }
    static func launchAtLoginUpdateFailed(_ message: String) -> String {
        format("launchAtLogin.updateFailed", "无法更新开机启动设置：%@", message)
    }
    static var onboardingWindowTitle: String { tr("onboarding.windowTitle", "准备使用") }
    static var onboardingReady: String { tr("onboarding.ready", "准备使用") }
    static var onboardingSkipNote: String { tr("onboarding.skipNote", "你可以跳过引导，之后从设置里重新打开。") }
    static var onboardingScreenRecordingExplanation: String { tr("onboarding.screenRecordingExplanation", "Pix 需要读取屏幕内容来完成截图、区域选择和录屏。") }
    static var onboardingAccessibilityExplanation: String { tr("onboarding.accessibilityExplanation", "Tran 需要辅助功能权限读取选中文本，Pix 也会用它识别窗口和控件位置。") }
    static var onboardingShortcutsExplanation: String { tr("onboarding.shortcutsExplanation", "确认常用全局快捷键。这里和设置页使用同一套配置，之后也可以随时修改。") }
    static var onboardingAuthorizeScreenRecording: String { tr("onboarding.authorizeScreenRecording", "授权屏幕录制") }
    static var onboardingRecheck: String { tr("onboarding.recheck", "重新检测") }
    static var onboardingSkip: String { tr("onboarding.skip", "跳过引导") }
    static var onboardingScreenRecordingAuthorizedMessage: String { tr("onboarding.screenRecordingAuthorizedMessage", "屏幕录制权限已授权。") }
    static var onboardingScreenRecordingPromptFallbackOpenedSettings: String {
        format("onboarding.screenRecordingPromptFallbackOpenedSettings", "系统没有弹出授权提示。已为你打开系统设置，请允许 %@ 录制屏幕后重新检测。", appName)
    }
    static var onboardingScreenRecordingPromptFallbackManual: String {
        format("onboarding.screenRecordingPromptFallbackManual", "系统没有弹出授权提示。请手动前往隐私与安全性中的屏幕录制，允许 %@ 后重新检测。", appName)
    }
    static var onboardingSettingsOpenedRecheck: String { tr("onboarding.settingsOpenedRecheck", "系统设置已打开。授权后回到这里点击重新检测。") }
    static var onboardingAccessibilitySettingsOpened: String {
        format("onboarding.accessibilitySettingsOpened", "系统设置已打开。打开 %@ 后回到这里点击重新检测。", appName)
    }
    static var onboardingScreenRecordingSettingsOpenFailed: String { tr("onboarding.screenRecordingSettingsOpenFailed", "无法打开系统设置，请手动前往隐私与安全性中的屏幕录制。") }
    static var onboardingAccessibilitySettingsOpenFailed: String { tr("onboarding.accessibilitySettingsOpenFailed", "无法打开系统设置，请手动前往隐私与安全性中的辅助功能。") }
    static var onboardingScreenRecordingTitle: String { tr("onboarding.screenRecordingTitle", "允许屏幕录制") }
    static var onboardingAccessibilityTitle: String { tr("onboarding.accessibilityTitle", "允许辅助功能") }
    static var onboardingShortcutsTitle: String { tr("onboarding.shortcutsTitle", "确认全局快捷键") }
    static var onboardingScreenRecordingSubtitle: String { tr("onboarding.screenRecordingSubtitle", "用于 Pix 截图、区域选择和录屏") }
    static var onboardingAccessibilitySubtitle: String { tr("onboarding.accessibilitySubtitle", "用于读取选中文本和识别窗口控件") }
    static var onboardingShortcutsSubtitle: String { tr("onboarding.shortcutsSubtitle", "让常用操作可以随手唤起") }
    static var onboardingAdjustable: String { tr("onboarding.adjustable", "可调整") }
    static var onboardingAuthorized: String { tr("onboarding.authorized", "已授权") }
    static var onboardingNotAuthorized: String { tr("onboarding.notAuthorized", "未授权") }
    static var onboardingCapabilityReady: String { tr("onboarding.capabilityReady", "这项能力已经准备好。") }
    static var onboardingCapabilityNeedsPermission: String { tr("onboarding.capabilityNeedsPermission", "授权后功能体验会更完整。") }
    static var updateCheckingProgress: String { tr("update.checkingProgress", "正在检查更新...") }
    static var updateDownloadingProgress: String { tr("update.downloadingProgress", "正在下载更新...") }
    static var updateExtractingProgress: String { tr("update.extractingProgress", "正在准备更新...") }
    static var updateReadyToInstallMessage: String { tr("update.readyToInstallMessage", "更新已准备好。安装完成后应用会重新启动。") }
    static var updateInstallingProgress: String { tr("update.installingProgress", "正在安装更新...") }
    static var updateInstalledMessage: String { tr("update.installedMessage", "更新已安装完成。") }
    static var updateAlreadyLatestMessage: String { tr("update.alreadyLatestMessage", "应用已经是最新版本。") }
    static var updateCheckFailedMessage: String { tr("update.checkFailedMessage", "无法完成更新检查。") }
    static var updateSkipVersion: String { tr("update.skipVersion", "跳过此版本") }
    static var updateReleaseNotes: String { tr("update.releaseNotes", "更新内容") }
    static var updateTitleAlreadyLatest: String { tr("update.titleAlreadyLatest", "已是最新版本") }
    static var updateTitleFailed: String { tr("update.titleFailed", "更新失败") }
    static var updateTitleReadyToInstall: String { tr("update.titleReadyToInstall", "可以安装了") }
    static var updateTitleInstalling: String { tr("update.titleInstalling", "正在安装更新...") }
    static var updateTitleInstalled: String { tr("update.titleInstalled", "更新已安装") }
    static var updateWindowTitle: String { tr("update.windowTitle", "更新") }
    static func updateAvailableTitle(_ version: String) -> String {
        format("update.availableTitle", "%@ 可用", version)
    }
    static func updateVersionSubtitle(current: String, latest: String) -> String {
        format("update.versionSubtitle", "当前 %@ -> 最新 %@", current, latest)
    }
    static var updateInstallAndRelaunch: String { tr("update.installAndRelaunch", "安装并重启") }
    static var updateInstall: String { tr("update.install", "安装更新") }
    static var updateDownloadedMessage: String { tr("update.downloadedMessage", "更新已下载完成。") }
    static var updateUnavailableDebugBuild: String { tr("update.unavailableDebugBuild", "Debug 构建不会检查更新；请使用 Release 构建测试更新。") }
    static var updateAvailableStatus: String { tr("update.availableStatus", "当前构建可使用自动更新。") }
    static var updateUnavailableConfiguration: String { tr("update.unavailableConfiguration", "当前构建未配置自动更新。") }
    static var updateUnavailableAlertTitle: String { tr("update.unavailableAlertTitle", "自动更新未配置") }
    static var updateUnavailableAlertMessage: String { tr("update.unavailableAlertMessage", "当前构建缺少检查更新所需配置。") }
    static var updateFrequencyDaily: String { tr("update.frequency.daily", "每天") }
    static var updateFrequencyWeekly: String { tr("update.frequency.weekly", "每周") }
    static var updateFrequencyMonthly: String { tr("update.frequency.monthly", "每月") }
}
