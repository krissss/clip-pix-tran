//
//  ContentView.swift
//  ClipPixTran
//
//  Created by kriss k on 2026/5/25.
//

import SwiftUI
import KeyboardShortcuts

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings

    @Bindable var clipboardMonitor: ClipboardMonitor
    @Bindable var screenshotController: ScreenshotController
    @Bindable var translationController: TranslationController
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
        .onAppear {
            clipboardMonitor.start()
        }
        .onDisappear {
            clipboardMonitor.stop()
        }
        .task {
            await observeShowClipShortcut()
        }
        .task {
            await observeCaptureSelectedRegionShortcut()
        }
        .task {
            await observeTranslateClipboardShortcut()
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

    private func observeShowClipShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClip) where event == .keyUp {
            selectedSection = .clip
            bringMainWindowForward()
        }
    }

    private func observeCaptureSelectedRegionShortcut() async {
        for await event in KeyboardShortcuts.events(for: .captureSelectedRegion) where event == .keyUp {
            selectedSection = .pix
            bringMainWindowForward()
            await screenshotController.captureSelectedRegion()
        }
    }

    private func observeTranslateClipboardShortcut() async {
        for await event in KeyboardShortcuts.events(for: .translateClipboardText) where event == .keyUp {
            guard let text = SystemClipboardService().readPlainText() else {
                continue
            }

            translationController.prefillSourceText(text)
            selectedSection = .tran
            bringMainWindowForward()
            await translationController.translate()
        }
    }

    private func bringMainWindowForward() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
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
        )
    )
}
