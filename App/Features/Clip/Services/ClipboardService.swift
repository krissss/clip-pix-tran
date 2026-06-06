import Foundation

protocol ClipboardService {
    var changeCount: Int { get }

    func readItem() -> ClipboardItem?
    func writeItem(_ item: ClipboardItem) throws
    func readPlainText() -> String?
    func writePlainText(_ text: String) throws
}

enum ClipboardWriteError: LocalizedError, Equatable {
    case rejected

    var errorDescription: String? {
        switch self {
        case .rejected:
            "无法写入剪贴板。"
        }
    }
}
