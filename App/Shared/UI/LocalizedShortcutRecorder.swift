import KeyboardShortcuts
import SwiftUI

struct LocalizedShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        context.coordinator.attach(to: recorder)
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        context.coordinator.attach(to: recorder)
        recorder.shortcutName = name
        context.coordinator.applyLocalization()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var recorder: KeyboardShortcuts.RecorderCocoa?
        private var beginObserver: NSObjectProtocol?
        private var endObserver: NSObjectProtocol?

        deinit {
            if let beginObserver {
                NotificationCenter.default.removeObserver(beginObserver)
            }

            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
        }

        func attach(to recorder: KeyboardShortcuts.RecorderCocoa) {
            guard self.recorder !== recorder else {
                applyLocalization()
                return
            }

            removeObservers()
            self.recorder = recorder
            beginObserver = NotificationCenter.default.addObserver(
                forName: NSControl.textDidBeginEditingNotification,
                object: recorder,
                queue: .main
            ) { [weak self] _ in
                self?.applyLocalization()
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: NSControl.textDidEndEditingNotification,
                object: recorder,
                queue: .main
            ) { [weak self] _ in
                self?.applyLocalization()
            }

            applyLocalization()
        }

        func applyLocalization() {
            guard let recorder, recorder.stringValue.isEmpty else {
                return
            }

            let isRecording = recorder.currentEditor() != nil
            recorder.placeholderString = isRecording ? L10n.shortcutPress : L10n.shortcutRecord
        }

        private func removeObservers() {
            if let beginObserver {
                NotificationCenter.default.removeObserver(beginObserver)
                self.beginObserver = nil
            }

            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
        }
    }
}
