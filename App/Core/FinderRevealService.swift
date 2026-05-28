import AppKit
import Foundation

enum FinderRevealService {
    @MainActor
    static func revealFirstPath(in item: ClipboardItem) {
        guard let path = item.filePaths.first else {
            return
        }

        reveal(path: path)
    }

    @MainActor
    static func reveal(path: String) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return
        }

        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: parentPath)
    }
}
