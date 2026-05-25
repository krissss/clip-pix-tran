import AppKit

struct SystemClipboardService: ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func readPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    func writePlainText(_ text: String) throws {
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)
        if !didWrite {
            throw ClipboardWriteError.rejected
        }
    }
}
