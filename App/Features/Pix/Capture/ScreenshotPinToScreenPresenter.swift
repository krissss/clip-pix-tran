import AppKit
import SwiftUI

@MainActor
protocol ScreenshotPinning: AnyObject {
    func pinPNGData(_ data: Data, sourceRect: CGRect?) throws
}

enum ScreenshotPinError: LocalizedError, Equatable {
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            L10n.screenshotPinFailed
        }
    }
}

@MainActor
final class ScreenshotPinToScreenPresenter: ScreenshotPinning {
    private var windowControllers: [UUID: PinnedScreenshotWindowController] = [:]

    func pinPNGData(_ data: Data, sourceRect: CGRect?) throws {
        guard let image = NSImage(data: data) else {
            throw ScreenshotPinError.invalidImageData
        }

        let id = UUID()
        let windowController = PinnedScreenshotWindowController(
            id: id,
            image: image,
            frame: initialFrame(for: image, sourceRect: sourceRect),
            onClose: { [weak self] id in
                self?.windowControllers[id] = nil
            }
        )
        windowControllers[id] = windowController
        windowController.showPinnedWindow()
    }

    private func initialFrame(for image: NSImage, sourceRect: CGRect?) -> CGRect {
        let screen = screen(for: sourceRect)
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 960, height: 640)
        let screenScale = max(screen?.backingScaleFactor ?? 1, 1)

        if let sourceRect {
            return clamped(
                sourceRect.standardized.pixelAligned(scale: screenScale),
                to: visibleFrame,
                scale: screenScale
            )
        }

        let imageSize = image.bestAvailableSize.scaled(by: 1 / screenScale)
        let maxSize = CGSize(
            width: max(160, visibleFrame.width * 0.72),
            height: max(120, visibleFrame.height * 0.72)
        )
        let fittedSize = imageSize.fitted(maxSize: maxSize)
        let frame = CGRect(
            x: visibleFrame.midX - fittedSize.width / 2,
            y: visibleFrame.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        return clamped(frame, to: visibleFrame, scale: screenScale)
    }

    private func screen(for sourceRect: CGRect?) -> NSScreen? {
        if let sourceRect {
            return NSScreen.screens.first { $0.frame.intersects(sourceRect) }
                ?? NSScreen.main
        }

        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
    }

    private func clamped(_ frame: CGRect, to visibleFrame: CGRect, scale: CGFloat) -> CGRect {
        let alignedFrame = frame.pixelAligned(scale: scale)
        let size = CGSize(
            width: min(max(alignedFrame.width, 1), visibleFrame.width),
            height: min(max(alignedFrame.height, 1), visibleFrame.height)
        )
        let origin = CGPoint(
            x: min(max(alignedFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(alignedFrame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
        return CGRect(origin: origin, size: size).pixelAligned(scale: scale)
    }
}

private final class PinnedScreenshotWindowController: NSWindowController, NSWindowDelegate {
    private let id: UUID
    private let hostingView: NSHostingView<PinnedScreenshotView>
    private let onClose: (UUID) -> Void

    init(
        id: UUID,
        image: NSImage,
        frame: CGRect,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.onClose = onClose

        let rootView = PinnedScreenshotView(
            image: image,
            onClose: {}
        )
        hostingView = NSHostingView(rootView: rootView)

        let window = PinnedScreenshotPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true

        super.init(window: window)

        hostingView.rootView = PinnedScreenshotView(
            image: image,
            onClose: { [weak window] in
                window?.close()
            }
        )
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPinnedWindow() {
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [id, onClose] in
            onClose(id)
        }
    }

    deinit {
        window?.delegate = nil
    }
}

private final class PinnedScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }

        super.keyDown(with: event)
    }
}

private struct PinnedScreenshotView: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onClose)

            controls
                .padding(6)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button {
                copyToPasteboard()
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 20, height: 20)
            }
            .help(L10n.pixCopyScreenshot)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 20, height: 20)
            }
            .help(L10n.screenshotClosePinned)
        }
        .buttonStyle(.borderless)
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}

private extension NSImage {
    var bestAvailableSize: CGSize {
        guard let representation = representations.max(by: { first, second in
            first.pixelsWide * first.pixelsHigh < second.pixelsWide * second.pixelsHigh
        }) else {
            return size
        }

        return CGSize(
            width: max(1, representation.pixelsWide),
            height: max(1, representation.pixelsHigh)
        )
    }
}

private extension CGSize {
    func scaled(by scale: CGFloat) -> CGSize {
        CGSize(width: width * scale, height: height * scale)
    }

    func fitted(maxSize: CGSize) -> CGSize {
        guard width > 0,
              height > 0,
              maxSize.width > 0,
              maxSize.height > 0 else {
            return CGSize(width: 320, height: 220)
        }

        let ratio = min(1, maxSize.width / width, maxSize.height / height)
        return CGSize(
            width: max(1, width * ratio),
            height: max(1, height * ratio)
        )
    }
}

private extension CGRect {
    func pixelAligned(scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        let minX = (minX * scale).rounded() / scale
        let minY = (minY * scale).rounded() / scale
        let maxX = (maxX * scale).rounded() / scale
        let maxY = (maxY * scale).rounded() / scale
        let minimumSize = 1 / scale

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, minimumSize),
            height: max(maxY - minY, minimumSize)
        )
    }
}
