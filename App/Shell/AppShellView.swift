//
//  AppShellView.swift
//  ClipPixTran
//
//  Created by kriss k on 2026/5/25.
//

import SwiftUI

struct AppShellView: View {
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
                        isSelected: selectedSection == section
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
                .padding(.vertical, 8)
                .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("打开设置")
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .controlPanelSidebarSurface(.navigation)
    }

    private var sidebarHeader: some View {
        VStack(spacing: 7) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .controlPanelRoundedSurface(
                    background: Color.accentColor.opacity(0.13),
                    cornerRadius: ControlPanelDesign.cardRadius
                )

            #if DEBUG
            DebugBuildBadge()
            #endif
        }
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
            TranslationView(controller: translationController)
        }
    }

    private func sendClipboardItemToTran(_ item: ClipboardItem) {
        translationController.prefillSourceText(item.text)
        selectedSection = .tran
    }

}

#if DEBUG
private struct DebugBuildBadge: View {
    var body: some View {
        Text("DEBUG")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(nsColor: .systemRed))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .stroke(Color(nsColor: .systemRed).opacity(0.24), lineWidth: 1)
            }
            .help("Debug 构建")
            .accessibilityLabel("Debug 构建")
    }
}
#endif

private struct SidebarSectionButton: View {
    let section: AppSection
    let isSelected: Bool
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
    AppShellView(
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
