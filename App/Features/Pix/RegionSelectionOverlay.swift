import AppKit

@MainActor
final class RegionSelectionOverlay {
    private static var activeOverlay: RegionSelectionOverlay?

    private var continuation: CheckedContinuation<CGRect, Error>?
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var didFinish = false

    static func selectRegion() async throws -> CGRect {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let overlay = RegionSelectionOverlay(continuation: continuation)
                activeOverlay = overlay
                overlay.show()
            }
        } onCancel: {
            Task { @MainActor in
                cancelActiveSelection()
            }
        }
    }

    static func cancelActiveSelection() {
        activeOverlay?.finish(.failure(ScreenshotCaptureError.cancelled))
    }

    private init(continuation: CheckedContinuation<CGRect, Error>) {
        self.continuation = continuation
    }

    private func show() {
        guard !NSScreen.screens.isEmpty else {
            finish(.failure(ScreenshotCaptureError.unavailable))
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        installMonitors()
        windows = NSScreen.screens.map { screen in
            let view = RegionSelectionView(screenFrame: screen.frame) { [weak self] result in
                self?.finish(result)
            }
            let window = RegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            return window
        }

        NSCursor.crosshair.set()
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else {
                return event
            }

            Task { @MainActor in
                Self.cancelActiveSelection()
            }
            return nil
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                Self.cancelActiveSelection()
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func finish(_ result: Result<CGRect, Error>) {
        guard !didFinish else {
            return
        }

        didFinish = true
        removeMonitors()
        NSCursor.arrow.set()
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        if Self.activeOverlay === self {
            Self.activeOverlay = nil
        }

        let pendingContinuation = continuation
        continuation = nil

        DispatchQueue.main.async {
            switch result {
            case .success(let rect):
                pendingContinuation?.resume(returning: rect)
            case .failure(let error):
                pendingContinuation?.resume(throwing: error)
            }
        }
    }
}

private final class RegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class RegionSelectionView: NSView {
    private let screenFrame: CGRect
    private let completion: (Result<CGRect, Error>) -> Void
    private var dragStart: CGPoint?
    private var dragEnd: CGPoint?

    private let minimumSelectionSize: CGFloat = 8

    init(
        screenFrame: CGRect,
        completion: @escaping (Result<CGRect, Error>) -> Void
    ) {
        self.screenFrame = screenFrame
        self.completion = completion
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))

        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(.failure(ScreenshotCaptureError.cancelled))
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragEnd = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)

        guard let selectionRect else {
            completion(.failure(ScreenshotCaptureError.cancelled))
            return
        }

        let rectInScreenSpace = selectionRect.offsetBy(
            dx: screenFrame.minX,
            dy: screenFrame.minY
        )
        completion(.success(rectInScreenSpace))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 1
        path.stroke()
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragEnd else {
            return nil
        }

        let rect = CGRect(
            x: min(dragStart.x, dragEnd.x),
            y: min(dragStart.y, dragEnd.y),
            width: abs(dragStart.x - dragEnd.x),
            height: abs(dragStart.y - dragEnd.y)
        ).intersection(bounds)

        guard rect.width >= minimumSelectionSize,
              rect.height >= minimumSelectionSize else {
            return nil
        }

        return rect
    }
}
