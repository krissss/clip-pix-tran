//
//  ContentView.swift
//  ClipPixTran
//
//  Created by kriss k on 2026/5/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings

    @Bindable var clipboardMonitor: ClipboardMonitor
    @Bindable var screenshotController: ScreenshotController
    @Bindable var translationController: TranslationController
    let shortcutController: AppShortcutController
    @Binding var selectedSection: AppSection

    var body: some View {
        HStack(spacing: ControlPanelDesign.Layout.splitSpacing) {
            mainSidebar
                .frame(width: ControlPanelDesign.Layout.mainSidebarWidth)

            sectionView(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ControlPanelBackground())
        .background(MainWindowRegistrationView())
    }

    private var mainSidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    SidebarSectionButton(
                        section: section,
                        isSelected: selectedSection == section,
                        countText: sidebarCountText(for: section)
                    ) {
                        selectedSection = section
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            Spacer(minLength: 16)

            Button {
                openSettings()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 30, height: 28)

                    Text("设置")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .help("打开设置")
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .controlPanelSidebarSurface(.navigation)
    }

    private var sidebarHeader: some View {
        Image(systemName: "sparkles.rectangle.stack")
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
            .frame(width: 38, height: 38)
            .controlPanelRoundedSurface(
                background: Color.accentColor.opacity(0.13),
                cornerRadius: ControlPanelDesign.cardRadius
            )
            .padding(.top, 16)
            .padding(.bottom, 4)
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

    private func sidebarCountText(for section: AppSection) -> String {
        switch section {
        case .clip:
            "\(clipboardMonitor.history.items.count)"
        case .pix:
            "\(screenshotController.history.items.count)"
        case .tran:
            "\(translationController.history.items.count)"
        }
    }

}

private struct SidebarSectionButton: View {
    let section: AppSection
    let isSelected: Bool
    let countText: String
    let action: () -> Void

    private var tint: Color {
        ControlPanelDesign.tint(for: section)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .frame(width: 30, height: 28)
                    .controlPanelRoundedSurface(
                        background: ControlPanelDesign.selectedFill(tint: tint, isSelected: isSelected, opacity: 0.13),
                        cornerRadius: ControlPanelDesign.compactRadius
                    )

                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Text(countText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            .controlPanelSelectedRow(isSelected: isSelected, tint: tint)
        }
        .buttonStyle(.plain)
        .help(section.title)
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
        ),
        selectedSection: .constant(.clip)
    )
}
