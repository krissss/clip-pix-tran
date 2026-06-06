import AppKit

protocol ScreenRecordingRegionOverlayPresenting: AnyObject {
    @MainActor
    var excludedWindowIDs: Set<CGWindowID> { get }

    @MainActor
    func show()
    @MainActor
    func close()
}

final class ScreenRecordingRegionOverlay: ScreenRecordingRegionOverlayPresenting {
    private var windows: [NSWindow] = []
    private let recordingRect: CGRect

    nonisolated init(recordingRect: CGRect) {
        self.recordingRect = recordingRect.standardized
    }

    @MainActor
    var excludedWindowIDs: Set<CGWindowID> {
        Set(windows.map { CGWindowID($0.windowNumber) })
    }

    @MainActor
    func show() {
        close()

        windows = NSScreen.screens.compactMap { screen in
            guard screen.frame.intersects(recordingRect) else {
                return nil
            }

            let view = ScreenRecordingRegionOverlayView(
                screenFrame: screen.frame,
                recordingRect: recordingRect
            )
            view.frame = CGRect(origin: .zero, size: screen.frame.size)

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            window.orderFrontRegardless()
            return window
        }
    }

    @MainActor
    func close() {
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        windows = []
    }
}

private final class ScreenRecordingRegionOverlayView: NSView {
    private let screenFrame: CGRect
    private let recordingRect: CGRect

    init(screenFrame: CGRect, recordingRect: CGRect) {
        self.screenFrame = screenFrame
        self.recordingRect = recordingRect.standardized
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let localRect = recordingRect
            .intersection(screenFrame)
            .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            .recordingOverlayPixelAligned(scale: window?.backingScaleFactor ?? 1)

        guard localRect.width > 0,
              localRect.height > 0 else {
            return
        }

        drawMask(excluding: localRect)
        drawBorder(outside: localRect)
        drawCornerHandles(outside: localRect)
        drawRecordingBadge(near: localRect)
    }

    private func drawMask(excluding rect: CGRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(rect: rect))
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.32).setFill()
        path.fill()
    }

    private func drawBorder(outside rect: CGRect) {
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: -5, dy: -5), xRadius: 3, yRadius: 3)
        border.lineWidth = 2
        NSColor.systemRed.setStroke()
        border.stroke()

        let glow = NSBezierPath(roundedRect: rect.insetBy(dx: -7, dy: -7), xRadius: 4, yRadius: 4)
        glow.lineWidth = 4
        NSColor.systemRed.withAlphaComponent(0.22).setStroke()
        glow.stroke()
    }

    private func drawCornerHandles(outside rect: CGRect) {
        let length: CGFloat = 18
        let gap: CGFloat = 5
        let minX = rect.minX - gap
        let maxX = rect.maxX + gap
        let minY = rect.minY - gap
        let maxY = rect.maxY + gap

        let path = NSBezierPath()
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: CGPoint(x: minX, y: minY + length))
        path.line(to: CGPoint(x: minX, y: minY))
        path.line(to: CGPoint(x: minX + length, y: minY))

        path.move(to: CGPoint(x: maxX - length, y: minY))
        path.line(to: CGPoint(x: maxX, y: minY))
        path.line(to: CGPoint(x: maxX, y: minY + length))

        path.move(to: CGPoint(x: minX, y: maxY - length))
        path.line(to: CGPoint(x: minX, y: maxY))
        path.line(to: CGPoint(x: minX + length, y: maxY))

        path.move(to: CGPoint(x: maxX - length, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY))
        path.line(to: CGPoint(x: maxX, y: maxY - length))

        NSColor.systemRed.setStroke()
        path.stroke()
    }

    private func drawRecordingBadge(near rect: CGRect) {
        let badgeSize = CGSize(width: 66, height: 26)
        let padding: CGFloat = 8
        var origin = CGPoint(
            x: rect.minX,
            y: rect.maxY + padding
        )
        if origin.y + badgeSize.height > bounds.maxY - padding {
            origin.y = rect.minY - badgeSize.height - padding
        }
        origin.x = min(max(origin.x, bounds.minX + padding), bounds.maxX - badgeSize.width - padding)

        let badgeRect = CGRect(origin: origin, size: badgeSize)
        guard bounds.contains(badgeRect),
              !badgeRect.intersects(rect) else {
            return
        }

        let background = NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.68).setFill()
        background.fill()

        let dotRect = CGRect(
            x: badgeRect.minX + 10,
            y: badgeRect.midY - 4,
            width: 8,
            height: 8
        )
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let text = "REC" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        text.draw(
            at: CGPoint(x: badgeRect.minX + 26, y: badgeRect.midY - 7),
            withAttributes: attributes
        )
    }
}

private extension CGRect {
    func recordingOverlayPixelAligned(scale: CGFloat) -> CGRect {
        let scale = max(scale, 1)
        return CGRect(
            x: floor(minX * scale) / scale,
            y: floor(minY * scale) / scale,
            width: ceil(width * scale) / scale,
            height: ceil(height * scale) / scale
        )
    }
}
