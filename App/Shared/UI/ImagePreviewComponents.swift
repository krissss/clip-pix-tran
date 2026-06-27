import AppKit
import ImageIO
import SwiftUI

struct ImageThumbnailView: View {
    let source: ImageDataSource
    let size: CGSize
    var cornerRadius: CGFloat = 6
    var maxPixelSize: Int = 240

    @State private var thumbnailImage: NSImage?
    @State private var didLoadThumbnail = false

    init(
        data: Data,
        size: CGSize,
        cornerRadius: CGFloat = 6,
        maxPixelSize: Int = 240
    ) {
        self.init(
            source: ImageDataSource(id: data.stableImageDataID, inlineData: data),
            size: size,
            cornerRadius: cornerRadius,
            maxPixelSize: maxPixelSize
        )
    }

    init(
        source: ImageDataSource,
        size: CGSize,
        cornerRadius: CGFloat = 6,
        maxPixelSize: Int = 240
    ) {
        self.source = source
        self.size = size
        self.cornerRadius = cornerRadius
        self.maxPixelSize = maxPixelSize
    }

    private var image: Image? {
        guard let thumbnailImage else {
            return nil
        }

        return Image(nsImage: thumbnailImage)
    }

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.quaternary)
                    }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: source.id) {
            thumbnailImage = nil
            didLoadThumbnail = false
            let imageSource = source
            let maxPixelSize = maxPixelSize
            thumbnailImage = await Task.detached(priority: .utility) {
                guard let sourceData = imageSource.loadData() else {
                    return nil
                }

                return ImageThumbnailRenderer.image(
                    from: sourceData,
                    maxPixelSize: maxPixelSize
                )
            }.value
            didLoadThumbnail = true
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size.width, height: size.height)
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

private extension Data {
    var stableImageDataID: String {
        "\(count)-\(prefix(32).reduce(UInt64(1469598103934665603)) { hash, byte in (hash ^ UInt64(byte)) &* 1099511628211 })"
    }
}

enum ImageThumbnailRenderer {
    nonisolated static func image(from data: Data, maxPixelSize: Int = 240) -> NSImage? {
        autoreleasepool {
            guard let cgImage = downsampledCGImage(
                from: data,
                maxPixelSize: maxPixelSize
            ) else {
                return nil
            }

            return NSImage(cgImage: cgImage, size: imageSize(for: cgImage))
        }
    }

    nonisolated static func pngData(from data: Data, maxPixelSize: Int = 240) -> Data? {
        autoreleasepool {
            guard let image = downsampledCGImage(
                from: data,
                maxPixelSize: maxPixelSize
            ) else {
                return nil
            }

            let bitmap = NSBitmapImageRep(cgImage: image)
            return bitmap.representation(using: .png, properties: [:])
        }
    }

    private nonisolated static func downsampledCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private nonisolated static func imageSize(for image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

@MainActor
final class ImagePreviewPresenter {
    private var windowController: ImagePreviewWindowController?

    func show(
        data: Data,
        title: String,
        subtitle: String,
        windowTitle: String,
        onCopy: @escaping () -> Void,
        onSave: (() -> Void)? = nil
    ) {
        let preview = ImagePreviewDetailView(
            data: data,
            title: title,
            subtitle: subtitle,
            onCopy: onCopy,
            onSave: onSave,
            onClose: { [weak self] in
                self?.close()
            }
        )

        if let windowController {
            windowController.update(rootView: preview, title: windowTitle)
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let windowController = ImagePreviewWindowController(
            rootView: preview,
            title: windowTitle,
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

private final class ImagePreviewWindowController: NSWindowController, NSWindowDelegate {
    private let hostingController: NSHostingController<ImagePreviewDetailView>
    private let onClose: () -> Void

    init(
        rootView: ImagePreviewDetailView,
        title: String,
        onClose: @escaping () -> Void
    ) {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
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

    func update(rootView: ImagePreviewDetailView, title: String) {
        hostingController.rootView = rootView
        window?.title = title
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async(execute: onClose)
    }

    deinit {
        window?.delegate = nil
    }
}

private struct ImagePreviewDetailView: View {
    let data: Data
    let title: String
    let subtitle: String
    let onCopy: () -> Void
    let onSave: (() -> Void)?
    let onClose: () -> Void

    @State private var zoomScale = 1.0
    @State private var nsImage: NSImage?
    @State private var didLoadImage = false

    private let minZoomScale = 0.25
    private let maxZoomScale = 4.0

    private var zoomPercentText: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    zoomScale = max(minZoomScale, zoomScale - zoomStep(for: zoomScale))
                } label: {
                    Label(L10n.commonZoomOut, systemImage: "minus.magnifyingglass")
                }
                .disabled(zoomScale <= minZoomScale)
                .help(L10n.commonZoomOut)

                Text(zoomPercentText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48)

                Button {
                    zoomScale = 1.0
                } label: {
                    Label(L10n.commonFitWindow, systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(zoomScale == 1.0)
                .help(L10n.commonFitWindow)

                Button {
                    zoomScale = min(maxZoomScale, zoomScale + zoomStep(for: zoomScale))
                } label: {
                    Label(L10n.commonZoomIn, systemImage: "plus.magnifyingglass")
                }
                .disabled(zoomScale >= maxZoomScale)
                .help(L10n.commonZoomIn)

                Button(action: onCopy) {
                    Label(L10n.commonCopy, systemImage: "doc.on.doc")
                }
                .help(L10n.commonCopyImage)

                if let onSave {
                    Button(action: onSave) {
                        Label(L10n.commonSave, systemImage: "square.and.arrow.down")
                    }
                    .help(L10n.commonSaveImage)
                }

                Button(L10n.commonDone) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ZStack {
                if let nsImage {
                    ZoomablePreviewImageView(
                        nsImage: nsImage,
                        zoomScale: zoomScale
                    )
                } else if didLoadImage {
                    ContentUnavailableView(
                        L10n.commonCannotPreviewImage,
                        systemImage: "exclamationmark.triangle"
                    )
                } else {
                    ProgressView()
                        .controlSize(.regular)
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
        .task(id: data) {
            nsImage = nil
            didLoadImage = false
            let sourceData = data
            nsImage = await Task.detached(priority: .utility) {
                ImageThumbnailRenderer.image(
                    from: sourceData,
                    maxPixelSize: 2400
                )
            }.value
            didLoadImage = true
        }
    }

    private func zoomStep(for scale: Double) -> Double {
        if scale < 1.0 {
            return 0.25
        }

        return 0.5
    }
}

private struct ZoomablePreviewImageView: View {
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
