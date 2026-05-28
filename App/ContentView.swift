//
//  ContentView.swift
//  ClipPixTran
//
//  Created by kriss k on 2026/5/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @Bindable var clipboardMonitor: ClipboardMonitor
    @Bindable var screenshotController: ScreenshotController
    @Bindable var translationController: TranslationController
    let shortcutController: AppShortcutController
    @State private var selectedSection: AppSection = .clip

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedSection) {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .scrollContentBackground(.hidden)

                Divider()

                Button {
                    openSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .help("打开设置")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .navigationTitle("ClipPixTran")
        } detail: {
            sectionView(for: selectedSection)
        }
        .background(MainWindowRegistrationView())
        .onAppear {
            shortcutController.selectSection = { section in
                selectedSection = section
            }
            shortcutController.openSection = { section in
                selectedSection = section
                if !AppWindowPresenter.bringMainWindowForward() {
                    openWindow(id: "main")
                    DispatchQueue.main.async {
                        AppWindowPresenter.bringMainWindowForward()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(for section: AppSection) -> some View {
        switch section {
        case .clip:
            ClipView(
                monitor: clipboardMonitor,
                translateAction: sendClipboardItemToTran
            )
        case .pix:
            PixView(controller: screenshotController)
        case .tran:
            TranView(controller: translationController)
        }
    }

    private func sendClipboardItemToTran(_ item: ClipboardItem) {
        translationController.prefillSourceText(item.text)
        selectedSection = .tran
    }

}

#Preview {
    ContentView(
        clipboardMonitor: ClipboardMonitor(
            pasteboard: PreviewClipboardService(),
            history: ClipboardHistoryStore.preview
        ),
        screenshotController: ScreenshotController(
            history: .preview,
            screenshotService: PreviewScreenshotService(),
            pasteboard: PreviewScreenshotPasteboardService(),
            fileSaver: PreviewScreenshotFileSaver()
        ),
        translationController: TranslationController(
            history: .preview,
            translationService: FallbackTranslationService(),
            pasteboard: PreviewClipboardService()
        ),
        shortcutController: AppShortcutController(
            clipboardMonitor: ClipboardMonitor(
                pasteboard: PreviewClipboardService(),
                history: ClipboardHistoryStore.preview
            ),
            screenshotController: ScreenshotController(
                history: .preview,
                screenshotService: PreviewScreenshotService(),
                pasteboard: PreviewScreenshotPasteboardService(),
                fileSaver: PreviewScreenshotFileSaver()
            ),
            translationController: TranslationController(
                history: .preview,
                translationService: FallbackTranslationService(),
                pasteboard: PreviewClipboardService()
            )
        )
    )
}
