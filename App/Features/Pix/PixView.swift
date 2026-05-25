import AppKit
import ImageIO
import SwiftUI

struct PixView: View {
    @Bindable var controller: ScreenshotController
    @State private var previewPresenter = ScreenshotPreviewPresenter()

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
            item: item,
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

    @State private var thumbnailData: Data?
    @State private var didLoadThumbnail = false

    private var image: Image? {
        guard let thumbnailData,
              let nsImage = NSImage(data: thumbnailData) else {
            return nil
        }

        return Image(nsImage: nsImage)
    }

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
        .task(id: item.id) {
            thumbnailData = nil
            didLoadThumbnail = false
            let data = item.data
            thumbnailData = await Task.detached(priority: .utility) {
                ScreenshotThumbnailRenderer.pngData(from: data)
            }.value
            didLoadThumbnail = true
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .frame(width: 120, height: 76)
            .overlay {
                if didLoadThumbnail {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
    }
}

private enum ScreenshotThumbnailRenderer {
    nonisolated static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
private final class ScreenshotPreviewPresenter {
    private var windowController: ScreenshotPreviewWindowController?

    func show(
        item: ScreenshotItem,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        let preview = ScreenshotDetailView(
            item: item,
            onCopy: onCopy,
            onSave: onSave,
            onClose: { [weak self] in
                self?.close()
            }
        )

        if let windowController {
            windowController.update(rootView: preview)
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let windowController = ScreenshotPreviewWindowController(
            rootView: preview,
            onClose: { [weak self] in
                self?.windowController = nil
            }
        )

        self.windowController = windowController
        windowController.window?.center()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        windowController?.window?.performClose(nil)
    }
}

private final class ScreenshotPreviewWindowController: NSWindowController, NSWindowDelegate {
    private let hostingController: NSHostingController<ScreenshotDetailView>
    private let onClose: () -> Void

    init(
        rootView: ScreenshotDetailView,
        onClose: @escaping () -> Void
    ) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "截图预览"
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        self.hostingController = hostingController
        self.onClose = onClose

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rootView: ScreenshotDetailView) {
        hostingController.rootView = rootView
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async(execute: onClose)
    }

    deinit {
        window?.delegate = nil
    }
}

private struct ScreenshotDetailView: View {
    let item: ScreenshotItem
    let onCopy: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void

    @State private var zoomScale = 1.0

    private let minZoomScale = 0.25
    private let maxZoomScale = 4.0

    private var nsImage: NSImage? {
        NSImage(data: item.data)
    }

    private var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("截图预览")
                        .font(.headline)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    zoomScale = max(minZoomScale, zoomScale - zoomStep(for: zoomScale))
                } label: {
                    Label("缩小", systemImage: "minus.magnifyingglass")
                }
                .disabled(zoomScale <= minZoomScale)
                .help("缩小截图")

                Text(zoomPercentText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48)

                Button {
                    zoomScale = 1.0
                } label: {
                    Label("适应窗口", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(zoomScale == 1.0)
                .help("适应窗口")

                Button {
                    zoomScale = min(maxZoomScale, zoomScale + zoomStep(for: zoomScale))
                } label: {
                    Label("放大", systemImage: "plus.magnifyingglass")
                }
                .disabled(zoomScale >= maxZoomScale)
                .help("放大截图")

                Button(action: onCopy) {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .help("复制截图")

                Button(action: onSave) {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .help("保存截图")

                Button("完成") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ZStack {
                if let nsImage {
                    ScreenshotZoomableImageView(
                        nsImage: nsImage,
                        zoomScale: zoomScale
                    )
                } else {
                    ContentUnavailableView(
                        "无法预览截图",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .frame(
                minWidth: 720,
                idealWidth: 720,
                maxWidth: .infinity,
                minHeight: 460,
                idealHeight: 460,
                maxHeight: .infinity
            )
        }
    }

    private func zoomStep(for scale: Double) -> Double {
        if scale < 1.0 {
            return 0.25
        }

        return 0.5
    }
}

private struct ScreenshotZoomableImageView: View {
    let nsImage: NSImage
    let zoomScale: Double

    var body: some View {
        GeometryReader { proxy in
            let availableSize = CGSize(
                width: max(1, proxy.size.width - 32),
                height: max(1, proxy.size.height - 32)
            )
            let fittedSize = fittedImageSize(
                imageSize: nsImage.size,
                availableSize: availableSize
            )
            let displaySize = CGSize(
                width: fittedSize.width * zoomScale,
                height: fittedSize.height * zoomScale
            )

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .padding(16)
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height
                    )
            }
        }
    }

    private func fittedImageSize(
        imageSize: CGSize,
        availableSize: CGSize
    ) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let widthRatio = availableSize.width / imageSize.width
        let heightRatio = availableSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)

        return CGSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
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
