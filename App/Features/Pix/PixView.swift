import AppKit
import SwiftUI

struct PixView: View {
    @Bindable var controller: ScreenshotController
    @State private var previewPresenter = ImagePreviewPresenter()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .navigationTitle("Pix")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("最近截图")
                    .font(.title3.weight(.semibold))

                Text("支持主屏幕截图和拖拽选区截图；标注和 OCR 会在后续里程碑继续扩展。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if controller.isCapturing {
                Button {
                    controller.stopCapture()
                } label: {
                    Label("停止", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task {
                        await controller.captureSelectedRegion()
                    }
                } label: {
                    Label("选区截图", systemImage: "selection.pin.in.out")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task {
                    await controller.captureMainDisplay()
                }
            } label: {
                Label("主屏幕", systemImage: "display")
            }
            .disabled(controller.isCapturing)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if controller.history.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    historyActions

                    if let errorMessage = controller.history.persistenceErrorMessage {
                        ScreenshotStatusRow(message: errorMessage)
                    }

                    if let errorMessage = controller.lastErrorMessage {
                        ScreenshotStatusRow(
                            message: errorMessage,
                            showsSettingsButton: controller.needsScreenRecordingPermission
                        )
                    }

                    ForEach(controller.history.items) { item in
                        ScreenshotItemRow(
                            item: item,
                            onCopy: {
                                controller.copyToPasteboard(item)
                            },
                            onSave: {
                                controller.save(item)
                            },
                            onPreview: {
                                showPreview(for: item)
                            },
                            onDelete: {
                                controller.delete(item)
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func showPreview(for item: ScreenshotItem) {
        previewPresenter.show(
            data: item.data,
            title: "截图预览",
            subtitle: item.createdAt.formatted(date: .abbreviated, time: .shortened),
            windowTitle: "截图预览",
            onCopy: {
                controller.copyToPasteboard(item)
            },
            onSave: {
                controller.save(item)
            }
        )
    }

    private var historyActions: some View {
        HStack {
            Label("\(controller.history.items.count) 张截图", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: controller.clearHistory) {
                Label("清空全部", systemImage: "trash")
            }
            .disabled(controller.history.items.isEmpty)
            .help("清空截图历史")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            Text("还没有截图")
                .font(.title3.weight(.semibold))

            if let errorMessage = controller.lastErrorMessage {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if controller.needsScreenRecordingPermission {
                        Button {
                            openScreenRecordingSettings()
                        } label: {
                            Label("打开系统设置", systemImage: "gearshape")
                        }
                    }
                }
            } else {
                Text("点击选区截图并拖拽选择屏幕区域。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct ScreenshotStatusRow: View {
    let message: String
    var showsSettingsButton = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)

            Text(message)
                .font(.callout)
                .foregroundStyle(.red)

            Spacer()

            if showsSettingsButton {
                Button {
                    openScreenRecordingSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private func openScreenRecordingSettings() {
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    ) else {
        return
    }

    NSWorkspace.shared.open(url)
}

private struct ScreenshotItemRow: View {
    let item: ScreenshotItem
    let onCopy: () -> Void
    let onSave: () -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void

    private var createdAtText: String {
        item.createdAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private var fileSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(item.data.count),
            countStyle: .file
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture(count: 2, perform: onPreview)
                .help("双击预览截图")

            VStack(alignment: .leading, spacing: 6) {
                Text(createdAtText)
                    .font(.headline)

                Text(fileSizeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .help("复制截图")

                Button(action: onSave) {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .help("保存截图")

                Button(action: onPreview) {
                    Label("预览", systemImage: "eye")
                }
                .help("预览截图")

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                .help("删除截图")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .frame(height: 96)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        ImageThumbnailView(
            data: item.data,
            size: CGSize(width: 120, height: 76)
        )
    }
}

#Preview {
    PixView(
        controller: ScreenshotController(
            history: .preview,
            screenshotService: PreviewScreenshotService(),
            pasteboard: PreviewScreenshotPasteboardService(),
            fileSaver: PreviewScreenshotFileSaver()
        )
    )
}
