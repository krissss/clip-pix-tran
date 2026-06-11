import AppKit
import ApplicationServices
import Foundation

protocol TextSelectionService {
    @MainActor func selectedText() async -> String?
}

struct SystemTextSelectionService: TextSelectionService {
    private let accessibilityGrabber: @MainActor () -> String?
    private let clipboardGrabber: @MainActor () async -> String?

    init(
        accessibilityGrabber: @escaping @MainActor () -> String? = {
            AccessibilitySelectedTextGrabber.grabSelectedText()
        },
        clipboardGrabber: @escaping @MainActor () async -> String? = {
            await ClipboardSelectedTextGrabber.grabSelectedText()
        }
    ) {
        self.accessibilityGrabber = accessibilityGrabber
        self.clipboardGrabber = clipboardGrabber
    }

    @MainActor
    func selectedText() async -> String? {
        if let text = cleanText(accessibilityGrabber()) {
            return text
        }

        return await cleanText(clipboardGrabber())
    }

    private func cleanText(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedText.isEmpty ? nil : trimmedText
    }
}

enum TextSelectionError: LocalizedError, Equatable {
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSelection:
            L10n.textSelectionNoSelection
        }
    }
}

private enum AccessibilitySelectedTextGrabber {
    @MainActor
    static func grabSelectedText() -> String? {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return nil
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(
            frontmostApplication.processIdentifier
        )

        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )

        guard selectedResult == .success,
              let selectedText = selectedValue as? String,
              !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }
}

private enum ClipboardSelectedTextGrabber {
    private static let syntheticEventTag: Int64 = 0x43505472 // "CPTr"
    @MainActor private static var isGrabbing = false

    @MainActor
    static func grabSelectedText() async -> String? {
        guard !isGrabbing else {
            return nil
        }

        isGrabbing = true
        defer { isGrabbing = false }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let savedItems = savedPasteboardItems(from: pasteboard)
        let userCopyDetector = LockedFlag()

        let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.keyCode == 0x08,
               event.cgEvent?.getIntegerValueField(.eventSourceUserData) != syntheticEventTag {
                userCopyDetector.setTrue()
            }
        }
        defer {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
        }

        simulateCopy()

        let deadline = Date().addingTimeInterval(0.25)
        while pasteboard.changeCount == previousChangeCount, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        guard pasteboard.changeCount != previousChangeCount else {
            return nil
        }

        let copiedChangeCount = pasteboard.changeCount
        let isFileSelection = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        let selectedText = isFileSelection ? nil : pasteboard.string(forType: .string)

        try? await Task.sleep(for: .milliseconds(30))

        let externalModification = pasteboard.changeCount != copiedChangeCount
            || userCopyDetector.value
        if !externalModification {
            restorePasteboardItems(savedItems, to: pasteboard)
        }

        guard let selectedText, !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }

    private static func savedPasteboardItems(
        from pasteboard: NSPasteboard
    ) -> [[(NSPasteboard.PasteboardType, Data)]]? {
        pasteboard.pasteboardItems?.compactMap { item in
            let values = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }

                return (type, data)
            }

            return values.isEmpty ? nil : values
        }
    }

    private static func restorePasteboardItems(
        _ savedItems: [[(NSPasteboard.PasteboardType, Data)]]?,
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()

        guard let savedItems else {
            return
        }

        let pasteboardItems = savedItems.map { values in
            let item = NSPasteboardItem()
            values.forEach { type, data in
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    private static func simulateCopy() {
        simulateCommandKey(0x08)
    }

    private static func simulateCommandKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}

private final class LockedFlag {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func setTrue() {
        lock.lock()
        storedValue = true
        lock.unlock()
    }
}
