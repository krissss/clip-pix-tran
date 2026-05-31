import AppKit
import ImageIO
import SwiftUI

@MainActor
final class RegionSelectionOverlay {
    private static var activeOverlay: RegionSelectionOverlay?

    typealias CaptureProvider = (CGRect, Set<CGWindowID>) async throws -> Data

    private var continuation: CheckedContinuation<ScreenshotCaptureOutput, Error>?
    private var windows: [NSWindow] = []
    private var selectionViews: [RegionSelectionView] = []
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var didFinish = false
    private var activeBaseCaptureID: UUID?
    private let captureProvider: CaptureProvider
    private let autoSelectionDetector: ScreenshotAutoSelectionDetecting
    private let annotationStore = ScreenshotAnnotationStore()

    static func capture(
        autoSelectionDetector: ScreenshotAutoSelectionDetecting? = nil,
        captureProvider: @escaping CaptureProvider
    ) async throws -> ScreenshotCaptureOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let overlay = RegionSelectionOverlay(
                    continuation: continuation,
                    autoSelectionDetector: autoSelectionDetector,
                    captureProvider: captureProvider
                )
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

    private init(
        continuation: CheckedContinuation<ScreenshotCaptureOutput, Error>,
        autoSelectionDetector: ScreenshotAutoSelectionDetecting?,
        captureProvider: @escaping CaptureProvider
    ) {
        self.continuation = continuation
        self.autoSelectionDetector = autoSelectionDetector ?? SystemScreenshotAutoSelectionDetector()
        self.captureProvider = captureProvider
    }

    private func show() {
        guard !NSScreen.screens.isEmpty else {
            finish(.failure(ScreenshotCaptureError.unavailable))
            return
        }

        installMonitors()
        windows = NSScreen.screens.map { screen in
            let view = RegionSelectionView(
                screenFrame: screen.frame,
                screenScale: screen.backingScaleFactor,
                annotationStore: annotationStore,
                actions: RegionSelectionActions(
                    finish: { [weak self] completion in
                        self?.complete(completion: completion)
                    },
                    cancel: { [weak self] in
                        self?.finish(.failure(ScreenshotCaptureError.cancelled))
                    },
                    requestBaseImageCapture: { [weak self] view, screenRect in
                        self?.captureBaseImage(for: view, screenRect: screenRect)
                    },
                    detectAutoSelectionRect: { [weak self] screenPoint in
                        guard let self else {
                            return nil
                        }

                        return self.autoSelectionDetector.autoSelectionRect(
                            at: screenPoint,
                            excludingWindowIDs: self.excludedWindowIDs
                        )
                    },
                    setNeedsDisplayOnAllScreens: { [weak self] in
                        self?.setNeedsDisplayOnAllScreens()
                    }
                )
            )
            selectionViews.append(view)

            let window = RegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            return window
        }

        NSCursor.crosshair.set()
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.finish(.failure(ScreenshotCaptureError.cancelled))
                }
                return nil
            }

            let command = event.modifierFlags.contains(.command)
            if command, event.charactersIgnoringModifiers?.lowercased() == "z" {
                Task { @MainActor [weak self] in
                    if event.modifierFlags.contains(.shift) {
                        self?.annotationStore.redo()
                    } else {
                        self?.annotationStore.undo()
                    }
                    self?.setNeedsDisplayOnAllScreens()
                }
                return nil
            }

            if event.keyCode == 36 {
                Task { @MainActor [weak self] in
                    self?.complete(completion: .copy)
                }
                return nil
            }

            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finish(.failure(ScreenshotCaptureError.cancelled))
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

    private func complete(completion: ScreenshotCaptureCompletion) {
        guard let selection = activeSelection else {
            finish(.failure(ScreenshotCaptureError.cancelled))
            return
        }

        activeBaseCaptureID = nil
        selectionViews.forEach { $0.prepareForCapture() }
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let baseData: Data
                if let cachedBaseData = selection.basePNGData {
                    baseData = cachedBaseData
                } else {
                    baseData = try await captureProvider(
                        selection.rect,
                        excludedWindowIDs
                    )
                }
                let data = try ScreenshotAnnotationRenderer.renderPNGData(
                    basePNGData: baseData,
                    annotations: translatedAnnotations(for: selection),
                    canvasSize: selection.rect.size
                )
                finish(
                    .success(
                        ScreenshotCaptureOutput(
                            data: data,
                            completion: completion,
                            sourceRect: selection.rect
                        )
                    )
                )
            } catch let error as ScreenshotCaptureError {
                finish(.failure(error))
            } catch {
                finish(.failure(ScreenshotCaptureError.pngEncodingFailed))
            }
        }
    }

    private func captureBaseImage(for view: RegionSelectionView, screenRect: CGRect) {
        guard !didFinish else {
            return
        }

        let captureID = UUID()
        activeBaseCaptureID = captureID

        Task { @MainActor [weak self, weak view] in
            guard let self else {
                return
            }

            defer {
                if self.activeBaseCaptureID == captureID {
                    self.activeBaseCaptureID = nil
                    if !self.didFinish {
                        self.setNeedsDisplayOnAllScreens()
                    }
                }
            }

            do {
                let baseData = try await self.captureProvider(
                    screenRect,
                    self.excludedWindowIDs
                )
                guard self.activeBaseCaptureID == captureID,
                      !self.didFinish else {
                    return
                }

                view?.setBaseImageData(baseData, for: screenRect)
                self.setNeedsDisplayOnAllScreens()
            } catch {
                guard self.activeBaseCaptureID == captureID else {
                    return
                }

                view?.clearBaseImage()
            }
        }
    }

    private var activeSelection: RegionSelectionSnapshot? {
        selectionViews
            .compactMap(\.selectionSnapshot)
            .max { first, second in
                first.rect.area < second.rect.area
            }
    }

    private func translatedAnnotations(for selection: RegionSelectionSnapshot) -> [ScreenshotAnnotation] {
        annotationStore.annotations.map { annotation in
            var translated = annotation
            translated.points = annotation.points.map { point in
                CGPoint(
                    x: point.x - selection.rect.minX,
                    y: point.y - selection.rect.minY
                )
            }
            return translated
        }
    }

    private func setNeedsDisplayOnAllScreens() {
        selectionViews.forEach { $0.needsDisplay = true }
    }

    private var excludedWindowIDs: Set<CGWindowID> {
        let selectionWindowIDs = windows.compactMap(\.windowNumber).map(CGWindowID.init)
        let toolbarWindowIDs = selectionViews.compactMap(\.toolbarWindowID)
        return Set(selectionWindowIDs + toolbarWindowIDs)
    }

    private func finish(_ result: Result<ScreenshotCaptureOutput, Error>) {
        guard !didFinish else {
            return
        }

        didFinish = true
        removeMonitors()
        NSCursor.arrow.set()
        selectionViews.forEach { $0.closeTransientUI() }
        selectionViews.removeAll()
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
            case .success(let output):
                pendingContinuation?.resume(returning: output)
            case .failure(let error):
                pendingContinuation?.resume(throwing: error)
            }
        }
    }
}

private struct RegionSelectionActions {
    let finish: (ScreenshotCaptureCompletion) -> Void
    let cancel: () -> Void
    let requestBaseImageCapture: (RegionSelectionView, CGRect) -> Void
    let detectAutoSelectionRect: (CGPoint) -> CGRect?
    let setNeedsDisplayOnAllScreens: () -> Void
}

private struct RegionSelectionSnapshot {
    let rect: CGRect
    let basePNGData: Data?
}

private final class RegionSelectionWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private enum RegionSelectionInteraction {
    case idle
    case autoSelecting(start: CGPoint, candidateRect: CGRect)
    case drawing(start: CGPoint)
    case moving(start: CGPoint, originalRect: CGRect)
    case resizing(handle: ScreenshotSelectionHandle, originalRect: CGRect)
    case annotating(start: CGPoint, annotationID: UUID)
    case movingAnnotation(id: UUID, start: CGPoint, originalAnnotation: ScreenshotAnnotation)
}

private struct RegionSelectionBaseImage {
    let screenRect: CGRect
    let pngData: Data
    let cgImage: CGImage
    let nsImage: NSImage
}

private enum RegionAnnotationTool: CaseIterable {
    case rectangle
    case ellipse
    case arrow
    case pen
    case text
    case mosaic

    var annotationKind: ScreenshotAnnotationKind {
        switch self {
        case .rectangle:
            .rectangle
        case .ellipse:
            .ellipse
        case .arrow:
            .arrow
        case .pen:
            .pen
        case .text:
            .text
        case .mosaic:
            .mosaic
        }
    }

    var usesStrokeOptions: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .pen:
            true
        case .text, .mosaic:
            false
        }
    }

    var title: String {
        switch self {
        case .rectangle:
            "矩形"
        case .ellipse:
            "椭圆"
        case .arrow:
            "箭头"
        case .pen:
            "画笔"
        case .text:
            "文字"
        case .mosaic:
            "马赛克"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle:
            "rectangle"
        case .ellipse:
            "circle"
        case .arrow:
            "arrow.up.right"
        case .pen:
            "pencil.tip"
        case .text:
            "textformat"
        case .mosaic:
            "checkerboard.rectangle"
        }
    }
}

private struct RegionToolbarState: Equatable {
    var activeTool: RegionAnnotationTool?
    var activeStyle: ScreenshotAnnotationStyle
    var canUndo: Bool
    var canRedo: Bool
}

private struct RegionToolbarActions {
    let setTool: (RegionAnnotationTool?) -> Void
    let setColor: (ScreenshotColorComponents) -> Void
    let setLineWidth: (CGFloat) -> Void
    let setFontSize: (CGFloat) -> Void
    let setMosaicMode: (ScreenshotMosaicMode) -> Void
    let setMosaicBlockSize: (CGFloat) -> Void
    let setMosaicBrushSize: (CGFloat) -> Void
    let undo: () -> Void
    let redo: () -> Void
    let pin: () -> Void
    let copy: () -> Void
    let save: () -> Void
    let cancel: () -> Void
    let finish: () -> Void
}

private final class RegionSelectionView: NSView {
    private static let manualSelectionDragThreshold: CGFloat = 3

    private let screenFrame: CGRect
    private let screenScale: CGFloat
    private let annotationStore: ScreenshotAnnotationStore
    private let actions: RegionSelectionActions
    private var selectionRect: CGRect?
    private var autoSelectionCandidateRect: CGRect?
    private var interaction: RegionSelectionInteraction = .idle
    private var activeTool: RegionAnnotationTool?
    private var activeStyle = ScreenshotAnnotationStyle()
    private var toolbarWindow: NSWindow?
    private var textEditor: NSTextField?
    private var hiddenForCapture = false
    private var baseImage: RegionSelectionBaseImage?
    private let annotationHitSlop: CGFloat = 8

    var toolbarWindowID: CGWindowID? {
        toolbarWindow.map { CGWindowID($0.windowNumber) }
    }

    var selectionSnapshot: RegionSelectionSnapshot? {
        guard let selectionRect else {
            return nil
        }

        let screenRect = screenRect(fromLocalRect: selectionRect)
        return RegionSelectionSnapshot(
            rect: screenRect,
            basePNGData: shouldDrawCapturedBaseImage
                && baseImage?.screenRect.isApproximatelyEqual(to: screenRect) == true ? baseImage?.pngData : nil
        )
    }

    init(
        screenFrame: CGRect,
        screenScale: CGFloat,
        annotationStore: ScreenshotAnnotationStore,
        actions: RegionSelectionActions
    ) {
        self.screenFrame = screenFrame
        self.screenScale = max(screenScale, 1)
        self.annotationStore = annotationStore
        self.actions = actions
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
        guard !hiddenForCapture else {
            return
        }

        addCursorRect(bounds, cursor: cursorForCurrentState)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            actions.cancel()
        } else if event.keyCode == 36 {
            actions.finish(.copy)
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !hiddenForCapture else {
            return
        }

        commitTextEditor()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if selectionRect == nil,
           let candidateRect = autoSelectionCandidateRect,
           candidateRect.contains(point) {
            interaction = .autoSelecting(start: point, candidateRect: candidateRect)
            hideToolbar()
            return
        }

        if let selectionRect {
            if let annotation = annotation(at: point, in: selectionRect) {
                annotationStore.prepareUndoForMutation()
                interaction = .movingAnnotation(
                    id: annotation.id,
                    start: screenPoint(fromLocalPoint: point),
                    originalAnnotation: annotation
                )
                hideToolbar()
                return
            }

            if let handle = ScreenshotSelectionGeometry.handle(at: point, in: selectionRect) {
                if handle == .move, activeTool != nil {
                    startAnnotation(at: point)
                } else if handle == .move {
                    interaction = .moving(start: point, originalRect: selectionRect)
                } else {
                    interaction = .resizing(handle: handle, originalRect: selectionRect)
                }
                hideToolbar()
                return
            }
        }

        selectionRect = nil
        autoSelectionCandidateRect = nil
        clearBaseImage()
        annotationStore.reset()
        interaction = .drawing(start: point)
        hideToolbar()
        needsDisplay = true
        actions.setNeedsDisplayOnAllScreens()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hiddenForCapture else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        switch interaction {
        case .idle:
            break
        case .autoSelecting(let start, let candidateRect):
            if distance(from: start, to: point) > Self.manualSelectionDragThreshold {
                selectionRect = nil
                autoSelectionCandidateRect = nil
                clearBaseImage()
                annotationStore.reset()
                interaction = .drawing(start: start)
                selectionRect = ScreenshotSelectionGeometry.rect(
                    from: start,
                    to: point,
                    clampedTo: bounds
                )
                .map(pixelAlignedLocalRect)
            } else {
                autoSelectionCandidateRect = candidateRect
            }
        case .drawing(let start):
            selectionRect = ScreenshotSelectionGeometry.rect(
                from: start,
                to: point,
                clampedTo: bounds
            )
            .map(pixelAlignedLocalRect)
            clearBaseImage()
        case .moving(let start, let originalRect):
            selectionRect = pixelAlignedLocalRect(
                ScreenshotSelectionGeometry.moved(
                    originalRect,
                    by: CGSize(
                        width: point.x - start.x,
                        height: point.y - start.y
                    ),
                    clampedTo: bounds
                )
            )
            clearBaseImage()
        case .resizing(let handle, let originalRect):
            selectionRect = pixelAlignedLocalRect(
                ScreenshotSelectionGeometry.resized(
                    originalRect,
                    handle: handle,
                    to: point,
                    clampedTo: bounds
                )
            )
            clearBaseImage()
        case .annotating(_, let annotationID):
            updateAnnotation(id: annotationID, to: point)
        case .movingAnnotation(let id, let start, let originalAnnotation):
            moveAnnotation(id: id, from: start, originalAnnotation: originalAnnotation, to: point)
        }

        needsDisplay = true
        actions.setNeedsDisplayOnAllScreens()
    }

    override func mouseUp(with event: NSEvent) {
        guard !hiddenForCapture else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        switch interaction {
        case .autoSelecting(_, let candidateRect):
            selectionRect = pixelAlignedLocalRect(candidateRect)
            autoSelectionCandidateRect = nil
            annotationStore.reset()
            clearBaseImage()
            interaction = .idle
            NSCursor.arrow.set()
            window?.invalidateCursorRects(for: self)
            showToolbarIfNeeded()
            requestBaseImageCaptureIfNeeded()
        case .drawing(let start):
            selectionRect = ScreenshotSelectionGeometry.rect(
                from: start,
                to: point,
                clampedTo: bounds
            )
            .map(pixelAlignedLocalRect)
            interaction = .idle
            NSCursor.arrow.set()
            window?.invalidateCursorRects(for: self)
            showToolbarIfNeeded()
            requestBaseImageCaptureIfNeeded()
        case .moving, .resizing:
            interaction = .idle
            showToolbarIfNeeded()
            requestBaseImageCaptureIfNeeded()
        case .annotating(_, let annotationID):
            updateAnnotation(id: annotationID, to: point)
            interaction = .idle
            finishTextAnnotationIfNeeded(id: annotationID)
            showToolbarIfNeeded()
        case .movingAnnotation(let id, let start, let originalAnnotation):
            moveAnnotation(id: id, from: start, originalAnnotation: originalAnnotation, to: point)
            interaction = .idle
            showToolbarIfNeeded()
        case .idle:
            break
        }

        updateAutoSelectionCandidate(at: point)
        needsDisplay = true
        actions.setNeedsDisplayOnAllScreens()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !hiddenForCapture else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        updateAutoSelectionCandidate(at: point)
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        actions.setNeedsDisplayOnAllScreens()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !hiddenForCapture else {
            return
        }

        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        if let selectionRect {
            NSColor.clear.setFill()
            selectionRect.fill(using: .clear)
            drawBaseImage(in: selectionRect)

            NSColor.white.withAlphaComponent(0.95).setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 1
            path.stroke()

            drawSelectionHandles(in: selectionRect)
            drawSizeBadge(for: selectionRect)
            drawAnnotations(in: selectionRect)
        } else if let autoSelectionCandidateRect {
            drawAutoSelectionCandidate(autoSelectionCandidateRect)
        }
    }

    func prepareForCapture() {
        hiddenForCapture = true
        closeTransientUI()
        needsDisplay = true
    }

    func setHiddenForBaseImageCapture(_ hidden: Bool) {
        hiddenForCapture = hidden
        if hidden {
            hideToolbar()
            autoSelectionCandidateRect = nil
        } else {
            showToolbarIfNeeded()
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setBaseImageData(_ data: Data, for capturedScreenRect: CGRect) {
        guard let selectionRect,
              screenRect(fromLocalRect: selectionRect).isApproximatelyEqual(to: capturedScreenRect),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        baseImage = RegionSelectionBaseImage(
            screenRect: capturedScreenRect,
            pngData: data,
            cgImage: cgImage,
            nsImage: NSImage(cgImage: cgImage, size: selectionRect.size)
        )
        needsDisplay = true
    }

    func clearBaseImage() {
        baseImage = nil
    }

    func closeTransientUI() {
        hideToolbar()
        autoSelectionCandidateRect = nil
        textEditor?.removeFromSuperview()
        textEditor = nil
    }

    private var cursorForCurrentState: NSCursor {
        guard let window,
              let selectionRect else {
            return .crosshair
        }

        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if annotation(at: point, in: selectionRect) != nil {
            return .openHand
        }

        guard let handle = ScreenshotSelectionGeometry.handle(at: point, in: selectionRect) else {
            return .arrow
        }

        switch handle {
        case .move:
            return activeTool == nil ? .arrow : .crosshair
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return .resizeLeftRight
        case .topRight, .bottomLeft:
            return .resizeLeftRight
        }
    }

    private func startAnnotation(at point: CGPoint) {
        guard let activeTool else {
            return
        }

        guard let selectionRect,
              selectionRect.contains(point) else {
            return
        }

        let annotation = ScreenshotAnnotation(
            kind: activeTool.annotationKind,
            points: initialPoints(for: activeTool, at: screenPoint(fromLocalPoint: point)),
            style: activeStyle,
            text: activeTool == .text ? "" : nil
        )
        annotationStore.append(annotation)
        interaction = .annotating(start: point, annotationID: annotation.id)
        if activeTool == .mosaic {
            requestBaseImageCaptureIfNeeded()
        }
        hideToolbar()
        needsDisplay = true
    }

    private func initialPoints(
        for tool: RegionAnnotationTool,
        at point: CGPoint
    ) -> [CGPoint] {
        switch tool {
        case .pen:
            [point]
        case .mosaic where activeStyle.mosaicMode == .brush:
            [point]
        default:
            [point, point]
        }
    }

    private func updateAnnotation(id: UUID, to localPoint: CGPoint) {
        guard let last = annotationStore.annotations.last,
              last.id == id,
              let selectionRect else {
            return
        }

        let clampedPoint = CGPoint(
            x: min(max(localPoint.x, selectionRect.minX), selectionRect.maxX),
            y: min(max(localPoint.y, selectionRect.minY), selectionRect.maxY)
        )
        let screenPoint = screenPoint(fromLocalPoint: clampedPoint)
        var annotation = last

        if annotation.kind == .pen || annotation.kind == .mosaic && annotation.style.mosaicMode == .brush {
            annotation.points.append(screenPoint)
        } else if annotation.points.count >= 2 {
            annotation.points[annotation.points.count - 1] = screenPoint
        }

        annotationStore.replaceLast(with: annotation)
    }

    private func moveAnnotation(
        id: UUID,
        from start: CGPoint,
        originalAnnotation: ScreenshotAnnotation,
        to localPoint: CGPoint
    ) {
        let current = screenPoint(fromLocalPoint: localPoint)
        let offset = CGSize(
            width: current.x - start.x,
            height: current.y - start.y
        )
        annotationStore.replace(
            id: id,
            with: originalAnnotation.translated(by: offset)
        )
    }

    private func finishTextAnnotationIfNeeded(id: UUID) {
        guard let annotation = annotationStore.annotations.last,
              annotation.id == id,
              annotation.kind == .text,
              let firstPoint = annotation.points.first else {
            return
        }

        let localPoint = localPoint(fromScreenPoint: firstPoint)
        let height = max(activeStyle.fontSize + 10, 28)
        let field = NSTextField(
            frame: CGRect(
                x: localPoint.x,
                y: localPoint.y,
                width: 180,
                height: height
            )
        )
        field.placeholderString = "文字"
        field.font = .systemFont(ofSize: activeStyle.fontSize, weight: .medium)
        field.textColor = activeStyle.nsColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.alignment = .left
        field.delegate = self
        addSubview(field)
        textEditor = field
        window?.makeFirstResponder(field)
    }

    private func commitTextEditor() {
        guard let textEditor,
              var annotation = annotationStore.annotations.last,
              annotation.kind == .text else {
            return
        }

        annotation.text = textEditor.stringValue
        let baselineOffset = textBaselineOffset(
            fontSize: annotation.style.fontSize,
            fieldHeight: textEditor.frame.height
        )
        annotation.points = [
            screenPoint(
                fromLocalPoint: CGPoint(
                    x: textEditor.frame.minX,
                    y: textEditor.frame.minY + baselineOffset
                )
            )
        ]
        if textEditor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotationStore.discardLatestChange()
        } else {
            annotationStore.replaceLast(with: annotation)
        }
        textEditor.removeFromSuperview()
        self.textEditor = nil
        needsDisplay = true
    }

    private func textBaselineOffset(fontSize: CGFloat, fieldHeight: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return max((fieldHeight - font.ascender - abs(font.descender)) / 2 + abs(font.descender), 0)
    }

    private func requestBaseImageCaptureIfNeeded() {
        guard let selectionRect,
              selectionRect.width > 0,
              selectionRect.height > 0 else {
            clearBaseImage()
            return
        }

        let screenRect = screenRect(fromLocalRect: selectionRect)
        guard baseImage?.screenRect.isApproximatelyEqual(to: screenRect) != true else {
            return
        }

        actions.requestBaseImageCapture(self, screenRect)
    }

    private func drawBaseImage(in selectionRect: CGRect) {
        guard shouldDrawCapturedBaseImage else {
            return
        }

        guard let baseImage,
              baseImage.screenRect.isApproximatelyEqual(to: screenRect(fromLocalRect: selectionRect)) else {
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .none
        baseImage.nsImage.draw(
            in: selectionRect,
            from: CGRect(origin: .zero, size: baseImage.nsImage.size),
            operation: .sourceOver,
            fraction: 1
        )
    }

    private var shouldDrawCapturedBaseImage: Bool {
        annotationStore.annotations.contains { annotation in
            annotation.kind == .mosaic
        }
    }

    private func updateAutoSelectionCandidate(at point: CGPoint) {
        guard case .idle = interaction,
              selectionRect == nil,
              activeTool == nil else {
            autoSelectionCandidateRect = nil
            return
        }

        guard let detectedRect = actions.detectAutoSelectionRect(
            screenPoint(fromLocalPoint: point)
        ) else {
            autoSelectionCandidateRect = nil
            return
        }

        let localRect = pixelAlignedLocalRect(localRect(fromScreenRect: detectedRect))
        guard localRect.contains(point),
              localRect.width >= ScreenshotSelectionGeometry.minimumSize.width,
              localRect.height >= ScreenshotSelectionGeometry.minimumSize.height else {
            autoSelectionCandidateRect = nil
            return
        }

        autoSelectionCandidateRect = localRect
    }

    private func drawSelectionHandles(in rect: CGRect) {
        NSColor.white.setFill()
        NSColor.black.withAlphaComponent(0.45).setStroke()
        for (_, handleRect) in ScreenshotSelectionGeometry.handleRects(for: rect) {
            let visibleRect = handleRect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: visibleRect, xRadius: 2, yRadius: 2)
            path.fill()
            path.stroke()
        }
    }

    private func drawAutoSelectionCandidate(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.clear.setFill()
        rect.fill(using: .clear)
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        path.fill()
        drawSizeBadge(for: rect)
    }

    private func drawSizeBadge(for rect: CGRect) {
        let text = "\(Int(rect.width)) x \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeRect = CGRect(
            x: rect.minX,
            y: max(bounds.minY + 8, rect.minY - textSize.height - 14),
            width: textSize.width + 14,
            height: textSize.height + 8
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 4),
            withAttributes: attributes
        )
    }

    private func drawAnnotations(in selectionRect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let annotations = annotationStore.annotations.map { annotation in
            var localAnnotation = annotation
            localAnnotation.points = annotation.points.map { point in
                let localPoint = localPoint(fromScreenPoint: point)
                return CGPoint(
                    x: localPoint.x - selectionRect.minX,
                    y: localPoint.y - selectionRect.minY
                )
            }
            return localAnnotation
        }
        let matchingBaseImage = baseImage?.screenRect.isApproximatelyEqual(
            to: screenRect(fromLocalRect: selectionRect)
        ) == true ? baseImage?.cgImage : nil

        context.saveGState()
        context.clip(to: selectionRect)
        context.translateBy(x: selectionRect.minX, y: selectionRect.minY)
        ScreenshotAnnotationRenderer.drawAnnotations(
            annotations,
            in: context,
            baseImage: matchingBaseImage,
            canvasSize: selectionRect.size
        )
        context.restoreGState()
    }

    private func annotation(at localPoint: CGPoint, in selectionRect: CGRect) -> ScreenshotAnnotation? {
        guard selectionRect.contains(localPoint) else {
            return nil
        }

        let screenPoint = screenPoint(fromLocalPoint: localPoint)
        return annotationStore.annotations.reversed().first { annotation in
            annotationContains(annotation, screenPoint: screenPoint)
        }
    }

    private func annotationContains(_ annotation: ScreenshotAnnotation, screenPoint: CGPoint) -> Bool {
        switch annotation.kind {
        case .rectangle, .ellipse:
            annotation.rect.insetBy(dx: -annotationHitSlop, dy: -annotationHitSlop).contains(screenPoint)
        case .mosaic where annotation.style.mosaicMode == .rectangle:
            annotation.rect.insetBy(dx: -annotationHitSlop, dy: -annotationHitSlop).contains(screenPoint)
        case .text:
            textHitRect(for: annotation).contains(screenPoint)
        case .arrow:
            pointsHitPath(annotation.points, point: screenPoint, tolerance: max(annotation.style.lineWidth + annotationHitSlop, 12))
        case .pen:
            pointsHitPath(annotation.points, point: screenPoint, tolerance: max(annotation.style.lineWidth + annotationHitSlop, 12))
        case .mosaic:
            pointsHitPath(annotation.points, point: screenPoint, tolerance: max(annotation.style.mosaicBrushSize / 2, 14))
        }
    }

    private func textHitRect(for annotation: ScreenshotAnnotation) -> CGRect {
        guard let origin = annotation.points.first,
              let text = annotation.text,
              !text.isEmpty else {
            return annotation.rect.insetBy(dx: -annotationHitSlop, dy: -annotationHitSlop)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .medium)
        ]
        let size = text.size(withAttributes: attributes)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(size.width, 18),
            height: max(size.height, annotation.style.fontSize + 6)
        )
        .insetBy(dx: -annotationHitSlop, dy: -annotationHitSlop)
    }

    private func pointsHitPath(
        _ points: [CGPoint],
        point: CGPoint,
        tolerance: CGFloat
    ) -> Bool {
        guard let first = points.first else {
            return false
        }

        if points.count == 1 {
            return distance(from: first, to: point) <= tolerance
        }

        return zip(points, points.dropFirst()).contains { start, end in
            distance(from: point, toSegmentFrom: start, to: end) <= tolerance
        }
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return distance(from: point, to: start)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return distance(from: point, to: projection)
    }

    private func showToolbarIfNeeded() {
        guard let selectionRect,
              toolbarWindow == nil else {
            positionToolbar()
            return
        }

        let toolbarView = RegionSelectionToolbarView(
            state: toolbarState,
            actions: toolbarActions
        )
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 560, height: 90)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(fittingSize.width, 1),
            height: max(fittingSize.height, 1)
        )

        let toolbarWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        toolbarWindow.contentView = hostingView
        toolbarWindow.backgroundColor = .clear
        toolbarWindow.isOpaque = false
        toolbarWindow.level = .screenSaver
        toolbarWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toolbarWindow.ignoresMouseEvents = false
        toolbarWindow.isReleasedWhenClosed = false
        toolbarWindow.orderFront(nil)
        self.toolbarWindow = toolbarWindow

        _ = selectionRect
        positionToolbar()
    }

    private func refreshToolbar() {
        guard let hostingView = toolbarWindow?.contentView as? NSHostingView<RegionSelectionToolbarView> else {
            return
        }

        hostingView.rootView = RegionSelectionToolbarView(
            state: toolbarState,
            actions: toolbarActions
        )
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        toolbarWindow?.setContentSize(
            CGSize(
                width: max(fittingSize.width, 1),
                height: max(fittingSize.height, 1)
            )
        )
        positionToolbar()
    }

    private var toolbarState: RegionToolbarState {
        RegionToolbarState(
            activeTool: activeTool,
            activeStyle: activeStyle,
            canUndo: annotationStore.canUndo,
            canRedo: annotationStore.canRedo
        )
    }

    private var toolbarActions: RegionToolbarActions {
        RegionToolbarActions(
            setTool: { [weak self] tool in
                self?.commitTextEditor()
                self?.activeTool = tool
                self?.refreshToolbar()
                guard let self else {
                    return
                }
                if tool == .mosaic {
                    self.requestBaseImageCaptureIfNeeded()
                }
                self.window?.invalidateCursorRects(for: self)
            },
            setColor: { [weak self] color in
                self?.activeStyle.colorComponents = color
                self?.refreshToolbar()
            },
            setLineWidth: { [weak self] lineWidth in
                self?.activeStyle.lineWidth = lineWidth
                self?.refreshToolbar()
            },
            setFontSize: { [weak self] fontSize in
                self?.activeStyle.fontSize = fontSize
                self?.refreshToolbar()
            },
            setMosaicMode: { [weak self] mode in
                self?.activeStyle.mosaicMode = mode
                self?.refreshToolbar()
            },
            setMosaicBlockSize: { [weak self] size in
                self?.activeStyle.mosaicBlockSize = size
                self?.refreshToolbar()
            },
            setMosaicBrushSize: { [weak self] size in
                self?.activeStyle.mosaicBrushSize = size
                self?.refreshToolbar()
            },
            undo: { [weak self] in
                self?.annotationStore.undo()
                self?.refreshToolbar()
                self?.actions.setNeedsDisplayOnAllScreens()
            },
            redo: { [weak self] in
                self?.annotationStore.redo()
                self?.refreshToolbar()
                self?.actions.setNeedsDisplayOnAllScreens()
            },
            pin: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.pinToScreen)
            },
            copy: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.copy)
            },
            save: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.save)
            },
            cancel: { [weak self] in
                self?.actions.cancel()
            },
            finish: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.copy)
            }
        )
    }

    private func positionToolbar() {
        guard let toolbarWindow,
              let selectionRect else {
            return
        }

        let toolbarSize = toolbarWindow.frame.size
        let screenRect = screenRect(fromLocalRect: selectionRect)
        let padding: CGFloat = 8
        var origin = CGPoint(
            x: screenRect.minX,
            y: screenRect.minY - toolbarSize.height - padding
        )

        if origin.y < screenFrame.minY + padding {
            origin.y = screenRect.maxY + padding
        }

        origin.x = min(
            max(origin.x, screenFrame.minX + padding),
            screenFrame.maxX - toolbarSize.width - padding
        )
        origin.y = min(
            max(origin.y, screenFrame.minY + padding),
            screenFrame.maxY - toolbarSize.height - padding
        )

        toolbarWindow.setFrameOrigin(origin)
    }

    private func hideToolbar() {
        toolbarWindow?.orderOut(nil)
        toolbarWindow?.close()
        toolbarWindow = nil
    }

    private func screenPoint(fromLocalPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + point.x,
            y: screenFrame.minY + point.y
        )
    }

    private func localPoint(fromScreenPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - screenFrame.minX,
            y: point.y - screenFrame.minY
        )
    }

    private func screenRect(fromLocalRect rect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + rect.minX,
            y: screenFrame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func localRect(fromScreenRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: rect.minY - screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func pixelAlignedLocalRect(_ rect: CGRect) -> CGRect {
        let screenRect = screenRect(fromLocalRect: rect.standardized)
            .pixelAligned(scale: screenScale)
        let localRect = localRect(fromScreenRect: screenRect)
            .intersection(bounds)

        guard !localRect.isNull else {
            return rect
        }

        return localRect
    }
}

extension RegionSelectionView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditor()
        showToolbarIfNeeded()
        actions.setNeedsDisplayOnAllScreens()
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }

        return width * height
    }

    func isApproximatelyEqual(to rect: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - rect.minX) <= tolerance
            && abs(minY - rect.minY) <= tolerance
            && abs(width - rect.width) <= tolerance
            && abs(height - rect.height) <= tolerance
    }

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

private struct RegionSelectionToolbarView: View {
    let state: RegionToolbarState
    let actions: RegionToolbarActions

    private let colors: [ScreenshotColorComponents] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .white,
        .black
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                toolButton(nil, symbolName: "hand.draw", title: "移动")

                ForEach(RegionAnnotationTool.allCases, id: \.self) { tool in
                    toolButton(tool, symbolName: tool.symbolName, title: tool.title)
                }

                Divider()
                    .frame(height: 22)

                Button(action: actions.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 22, height: 22)
                }
                .disabled(!state.canUndo)
                .help("撤销")

                Button(action: actions.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .frame(width: 22, height: 22)
                }
                .disabled(!state.canRedo)
                .help("重做")

                Button(action: actions.pin) {
                    Image(systemName: "pin")
                        .frame(width: 22, height: 22)
                }
                .help("固定到屏幕")

                Button(action: actions.save) {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 22, height: 22)
                }
                .help("保存")

                Button(action: actions.cancel) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .help("取消")

                Button(action: actions.finish) {
                    Image(systemName: "checkmark")
                        .frame(width: 22, height: 22)
                }
                .help("完成")
                .keyboardShortcut(.return, modifiers: [])
            }
            .buttonStyle(.borderless)
            .toolbarSurface()

            secondaryToolbar
                .buttonStyle(.borderless)
                .toolbarSurface()
                .transition(.opacity)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var secondaryToolbar: some View {
        Group {
            switch state.activeTool {
            case .rectangle, .ellipse, .arrow, .pen:
                strokeOptions
            case .text:
                textOptions
            case .mosaic:
                mosaicOptions
            case nil:
                EmptyView()
            }
        }
    }

    private var strokeOptions: some View {
        HStack(spacing: 10) {
            colorOptions
            Divider().frame(height: 22)
            sizeDots(
                values: [2, 4, 7],
                selected: state.activeStyle.lineWidth,
                action: actions.setLineWidth
            )
        }
    }

    private var textOptions: some View {
        HStack(spacing: 10) {
            colorOptions
            Divider().frame(height: 22)
            sizeDots(
                values: [16, 20, 26, 32],
                selected: state.activeStyle.fontSize,
                action: actions.setFontSize
            )
        }
    }

    private var mosaicOptions: some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(
                get: { state.activeStyle.mosaicMode },
                set: actions.setMosaicMode
            )) {
                Image(systemName: "rectangle.dashed").tag(ScreenshotMosaicMode.rectangle)
                Image(systemName: "scribble.variable").tag(ScreenshotMosaicMode.brush)
            }
            .pickerStyle(.segmented)
            .frame(width: 88)
            .help("马赛克模式")

            Divider().frame(height: 22)

            sizeDots(
                values: [8, 14, 22, 32],
                selected: state.activeStyle.mosaicBlockSize,
                action: actions.setMosaicBlockSize
            )
            .help("模糊块大小")

            if state.activeStyle.mosaicMode == .brush {
                Divider().frame(height: 22)
                sizeDots(
                    values: [16, 28, 44],
                    selected: state.activeStyle.mosaicBrushSize,
                    action: actions.setMosaicBrushSize
                )
                .help("涂抹范围")
            }
        }
    }

    private var colorOptions: some View {
        HStack(spacing: 10) {
            ForEach(colors, id: \.self) { color in
                Button {
                    actions.setColor(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .overlay {
                            Circle()
                                .stroke(.primary.opacity(color == state.activeStyle.colorComponents ? 0.8 : 0.18), lineWidth: 1)
                        }
                        .frame(width: color == state.activeStyle.colorComponents ? 18 : 14, height: color == state.activeStyle.colorComponents ? 18 : 14)
                        .frame(width: 22, height: 22)
                }
                .help("颜色")
            }
        }
    }

    private func sizeDots(
        values: [CGFloat],
        selected: CGFloat,
        action: @escaping (CGFloat) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ForEach(values, id: \.self) { value in
                Button {
                    action(value)
                } label: {
                    Circle()
                        .fill(.primary)
                        .frame(width: dotSize(for: value, in: values), height: dotSize(for: value, in: values))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(abs(value - selected) < 0.1 ? Color.accentColor.opacity(0.16) : .clear)
                        )
                }
            }
        }
    }

    private func dotSize(for value: CGFloat, in values: [CGFloat]) -> CGFloat {
        guard let minimum = values.min(),
              let maximum = values.max(),
              maximum > minimum else {
            return 12
        }

        return 6 + (value - minimum) / (maximum - minimum) * 12
    }

    private func toolButton(
        _ tool: RegionAnnotationTool?,
        symbolName: String,
        title: String
    ) -> some View {
        Button {
            actions.setTool(tool)
        } label: {
            Image(systemName: symbolName)
                .frame(width: 22, height: 22)
        }
        .help(title)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(tool == state.activeTool ? Color.accentColor.opacity(0.18) : .clear)
        )
    }
}

private extension View {
    func toolbarSurface() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
    }
}
