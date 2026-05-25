import Foundation

struct PreviewClipboardService: ClipboardService {
    var changeCount: Int { 0 }

    func readPlainText() -> String? {
        nil
    }

    func writePlainText(_ text: String) throws {
    }
}

extension ClipboardHistoryStore {
    static var preview: ClipboardHistoryStore {
        let store = ClipboardHistoryStore()
        store.record("ClipPixTran 的第一条剪贴板记录")
        store.record("稍长一点的文本会在列表里折行显示，方便快速识别内容。")
        store.record("重复复制同一段文本会把它移到顶部")
        return store
    }
}
