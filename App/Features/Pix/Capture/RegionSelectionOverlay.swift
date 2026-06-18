import AppKit
import ImageIO
import SwiftUI

@MainActor
final class RegionSelectionOverlay {
    private static var activeOverlay: RegionSelectionOverlay?

    typealias CaptureProvider = @Sendable (CGRect, Set<CGWindowID>) async throws -> Data

    private var continuation: CheckedContinuation<RegionSelectionOverlayResult, Error>?
    private var windows: [NSWindow] = []
    private var selectionViews: [RegionSelectionView] = []
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var cancelEventTap: RegionSelectionCancelEventTap?
    private var resignObserver: NSObjectProtocol?
    private var didFinish = false
    private var activeBaseCaptureID: UUID?
    private var scrollingCaptureSession: ScrollingScreenshotCaptureSession?
    private let captureProvider: CaptureProvider
    private let initialMode: ScreenshotRegionCaptureMode
    private let initialSnapshots: [ScreenCaptureSnapshot]
    private let autoSelectionDetector: ScreenshotAutoSelectionDetecting
    private let behavior: RegionSelectionBehavior
    private let annotationStore = ScreenshotAnnotationStore()

    static func capture(
        initialMode: ScreenshotRegionCaptureMode = .screenshot,
        initialSnapshots: [ScreenCaptureSnapshot] = [],
        autoSelectionDetector: ScreenshotAutoSelectionDetecting? = nil,
        captureProvider: @escaping CaptureProvider
    ) async throws -> ScreenshotCaptureOutput {
        try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation { continuation in
                let overlay = RegionSelectionOverlay(
                    continuation: continuation,
                    initialMode: initialMode,
                    initialSnapshots: initialSnapshots,
                    autoSelectionDetector: autoSelectionDetector,
                    behavior: .capture,
                    captureProvider: captureProvider
                )
                activeOverlay = overlay
                overlay.show()
            }
            guard case .capture(let output) = result else {
                throw ScreenshotCaptureError.unavailable
            }

            return output
        } onCancel: {
            Task { @MainActor in
                cancelActiveSelection()
            }
        }
    }

    static func selectRegion(
        initialSnapshots: [ScreenCaptureSnapshot] = [],
        autoSelectionDetector: ScreenshotAutoSelectionDetecting? = nil
    ) async throws -> CGRect {
        try await withTaskCancellationHandler {
            let result = try await withCheckedThrowingContinuation { continuation in
                let overlay = RegionSelectionOverlay(
                    continuation: continuation,
                    initialMode: .recording,
                    initialSnapshots: initialSnapshots,
                    autoSelectionDetector: autoSelectionDetector,
                    behavior: .selectRegion,
                    captureProvider: { _, _ in
                        throw ScreenshotCaptureError.unavailable
                    }
                )
                activeOverlay = overlay
                overlay.show()
            }
            guard case .region(let rect) = result else {
                throw ScreenshotCaptureError.unavailable
            }

            return rect
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
        continuation: CheckedContinuation<RegionSelectionOverlayResult, Error>,
        initialMode: ScreenshotRegionCaptureMode,
        initialSnapshots: [ScreenCaptureSnapshot],
        autoSelectionDetector: ScreenshotAutoSelectionDetecting?,
        behavior: RegionSelectionBehavior,
        captureProvider: @escaping CaptureProvider
    ) {
        self.continuation = continuation
        self.initialMode = initialMode
        self.initialSnapshots = initialSnapshots
        self.autoSelectionDetector = autoSelectionDetector ?? SystemScreenshotAutoSelectionDetector()
        self.behavior = behavior
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
                initialSnapshot: initialSnapshots.bestSnapshot(for: screen.frame),
                initialMode: initialMode,
                annotationStore: annotationStore,
                behavior: behavior,
                actions: RegionSelectionActions(
                    finish: { [weak self] completion in
                        self?.complete(completion: completion)
                    },
                    finishSelection: { [weak self] in
                        self?.completeSelection()
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
            window.cancelHandler = { [weak self] in
                self?.cancel()
            }
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            return window
        }

        NSCursor.crosshair.set()
    }

    private func installMonitors() {
        cancelEventTap = RegionSelectionCancelEventTap { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            if event.type == .rightMouseDown {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
                return nil
            }

            if event.keyCode == 53 {
                Task { @MainActor [weak self] in
                    self?.cancel()
                }
                return nil
            }

            let command = event.modifierFlags.contains(.command)
            if self.behavior == .capture,
               command,
               event.charactersIgnoringModifiers?.lowercased() == "z" {
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

            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return
            }

            Task { @MainActor [weak self] in
                self?.cancel()
            }
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

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        cancelEventTap = nil

        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func cancel() {
        finish(.failure(ScreenshotCaptureError.cancelled))
    }

    private func complete(completion: ScreenshotCaptureCompletion) {
        guard let selection = activeSelection else {
            finish(.failure(ScreenshotCaptureError.cancelled))
            return
        }

        if completion == .startRecording {
            finish(
                .success(
                    .capture(
                        ScreenshotCaptureOutput(
                            data: Data(),
                            completion: completion,
                            sourceRect: selection.rect
                        )
                    )
                )
            )
            return
        }

        if completion == .scrollingCapture {
            completeScrollingCapture(for: selection)
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
                } else if let snapshotBaseData = try selection.snapshot?.pngData(in: selection.rect) {
                    baseData = snapshotBaseData
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
                        .capture(
                            ScreenshotCaptureOutput(
                                data: data,
                                completion: completion,
                                sourceRect: selection.rect
                            )
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

    private func completeScrollingCapture(for selection: RegionSelectionSnapshot) {
        activeBaseCaptureID = nil
        removeMonitors()
        windows.forEach { window in
            window.ignoresMouseEvents = true
        }

        do {
            selectionViews.forEach {
                $0.beginScrollingCaptureProgress(
                    finish: { [weak self] in
                        self?.finishScrollingCapture(for: selection)
                    },
                    cancel: { [weak self] in
                        self?.cancelScrollingCapture()
                    }
                )
            }
            scrollingCaptureSession = try ScrollingScreenshotService().startManualCapture(
                in: selection.rect,
                excludingWindowIDs: excludedWindowIDs,
                captureProvider: captureProvider
            )
        } catch let error as ScreenshotCaptureError {
            finish(.failure(error))
        } catch {
            finish(.failure(ScreenshotCaptureError.unavailable))
        }
    }

    private func finishScrollingCapture(for selection: RegionSelectionSnapshot) {
        guard let session = scrollingCaptureSession else {
            finish(.failure(ScreenshotCaptureError.cancelled))
            return
        }

        scrollingCaptureSession = nil
        selectionViews.forEach { $0.prepareForCapture() }
        Task { [weak self, session] in
            guard let self else {
                return
            }

            do {
                let data = try await session.finish()
                finish(
                    .success(
                        .capture(
                            ScreenshotCaptureOutput(
                                data: data,
                                completion: .scrollingCapture,
                                sourceRect: selection.rect
                            )
                        )
                    )
                )
            } catch let error as ScreenshotCaptureError {
                finish(.failure(error))
            } catch is CancellationError {
                finish(.failure(ScreenshotCaptureError.cancelled))
            } catch {
                finish(.failure(ScreenshotCaptureError.unavailable))
            }
        }
    }

    private func cancelScrollingCapture() {
        let session = scrollingCaptureSession
        scrollingCaptureSession = nil
        Task {
            await session?.cancel()
        }
        finish(.failure(ScreenshotCaptureError.cancelled))
    }

    private func completeSelection() {
        guard let selection = activeSelection else {
            finish(.failure(ScreenshotCaptureError.cancelled))
            return
        }

        finish(.success(.region(selection.rect)))
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
        let statusWindowIDs = selectionViews.compactMap(\.statusWindowID)
        return Set(selectionWindowIDs + toolbarWindowIDs + statusWindowIDs)
    }

    private func finish(_ result: Result<RegionSelectionOverlayResult, Error>) {
        guard !didFinish else {
            return
        }

        didFinish = true
        removeMonitors()
        let session = scrollingCaptureSession
        scrollingCaptureSession = nil
        Task {
            await session?.cancel()
        }
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

private enum RegionSelectionOverlayResult {
    case capture(ScreenshotCaptureOutput)
    case region(CGRect)
}

private enum RegionSelectionBehavior {
    case capture
    case selectRegion
}

private struct RegionSelectionActions {
    let finish: (ScreenshotCaptureCompletion) -> Void
    let finishSelection: () -> Void
    let cancel: () -> Void
    let requestBaseImageCapture: (RegionSelectionView, CGRect) -> Void
    let detectAutoSelectionRect: (CGPoint) -> CGRect?
    let setNeedsDisplayOnAllScreens: () -> Void
}

private struct RegionSelectionSnapshot {
    let rect: CGRect
    let basePNGData: Data?
    let snapshot: ScreenCaptureSnapshot?
}

private final class RegionSelectionCancelEventTap {
    private let action: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        install()
    }

    deinit {
        uninstall()
    }

    private func install() {
        guard CGPreflightListenEventAccess() else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.handleEvent,
            userInfo: userInfo
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func uninstall() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<RegionSelectionCancelEventTap>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return monitor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .rightMouseDown || type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            Task { @MainActor [action] in
                action()
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

private final class RegionSelectionWindow: NSPanel {
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == 53:
            cancelHandler?()
        case .rightMouseDown:
            cancelHandler?()
        default:
            super.sendEvent(event)
        }
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

private enum RegionSelectionStatusOverlay {
    case scrollingCapture(finish: () -> Void, cancel: () -> Void)
}

extension RegionSelectionStatusOverlay: Equatable {
    static func == (lhs: RegionSelectionStatusOverlay, rhs: RegionSelectionStatusOverlay) -> Bool {
        switch (lhs, rhs) {
        case (.scrollingCapture, .scrollingCapture):
            true
        }
    }
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
            L10n.captureToolRectangle
        case .ellipse:
            L10n.captureToolEllipse
        case .arrow:
            L10n.captureToolArrow
        case .pen:
            L10n.captureToolPen
        case .text:
            L10n.captureToolText
        case .mosaic:
            L10n.captureToolMosaic
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
            "t.circle"
        case .mosaic:
            "checkerboard.rectangle"
        }
    }
}

private struct RegionToolbarState: Equatable {
    var captureMode: ScreenshotRegionCaptureMode
    var activeTool: RegionAnnotationTool?
    var activeStyle: ScreenshotAnnotationStyle
    var canUndo: Bool
    var canRedo: Bool
}

private struct RegionToolbarActions {
    let setCaptureMode: (ScreenshotRegionCaptureMode) -> Void
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
    let recognizeText: () -> Void
    let scrollingCapture: () -> Void
    let cancel: () -> Void
    let finish: () -> Void
    let startRecording: () -> Void
}

private final class RegionSelectionView: NSView {
    private static let manualSelectionDragThreshold: CGFloat = 3

    private let screenFrame: CGRect
    private let screenScale: CGFloat
    private let initialSnapshot: ScreenCaptureSnapshot?
    private let annotationStore: ScreenshotAnnotationStore
    private let behavior: RegionSelectionBehavior
    private let actions: RegionSelectionActions
    private var selectionRect: CGRect?
    private var autoSelectionCandidateRect: CGRect?
    private var interaction: RegionSelectionInteraction = .idle
    private var toolbarCaptureMode: ScreenshotRegionCaptureMode
    private var activeTool: RegionAnnotationTool?
    private var activeStyle = ScreenshotAnnotationStyle()
    private var toolbarWindow: NSWindow?
    private var statusWindow: NSWindow?
    private var textEditor: NSTextField?
    private var hiddenForCapture = false
    private var statusOverlay: RegionSelectionStatusOverlay? {
        didSet {
            guard statusOverlay != oldValue else {
                return
            }
            if let statusOverlay {
                showStatusControl(for: statusOverlay)
            } else {
                hideStatusControl()
            }
        }
    }
    private var baseImage: RegionSelectionBaseImage?
    private let annotationHitSlop: CGFloat = 8

    var toolbarWindowID: CGWindowID? {
        toolbarWindow.map { CGWindowID($0.windowNumber) }
    }

    var statusWindowID: CGWindowID? {
        statusWindow.map { CGWindowID($0.windowNumber) }
    }

    var selectionSnapshot: RegionSelectionSnapshot? {
        guard let selectionRect else {
            return nil
        }

        let screenRect = screenRect(fromLocalRect: selectionRect)
        return RegionSelectionSnapshot(
            rect: screenRect,
            basePNGData: shouldDrawCapturedBaseImage
                && baseImage?.screenRect.isApproximatelyEqual(to: screenRect) == true ? baseImage?.pngData : nil,
            snapshot: initialSnapshot
        )
    }

    init(
        screenFrame: CGRect,
        screenScale: CGFloat,
        initialSnapshot: ScreenCaptureSnapshot?,
        initialMode: ScreenshotRegionCaptureMode,
        annotationStore: ScreenshotAnnotationStore,
        behavior: RegionSelectionBehavior,
        actions: RegionSelectionActions
    ) {
        self.screenFrame = screenFrame
        self.screenScale = max(screenScale, 1)
        self.initialSnapshot = initialSnapshot
        self.toolbarCaptureMode = initialMode
        self.annotationStore = annotationStore
        self.behavior = behavior
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
        guard statusOverlay == nil else {
            return
        }

        if event.keyCode == 53 {
            actions.cancel()
        } else if event.keyCode == 36 {
            switch behavior {
            case .capture:
                finishPrimaryToolbarAction()
            case .selectRegion:
                actions.finishSelection()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard statusOverlay == nil else {
            return
        }

        actions.cancel()
    }

    override func mouseDown(with event: NSEvent) {
        guard !hiddenForCapture,
              statusOverlay == nil else {
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
            if behavior == .capture,
               toolbarCaptureMode == .screenshot,
               let annotation = annotation(at: point, in: selectionRect) {
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
                if handle == .move,
                   toolbarCaptureMode == .screenshot,
                   activeTool != nil {
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
        guard !hiddenForCapture,
              statusOverlay == nil else {
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
        guard !hiddenForCapture,
              statusOverlay == nil else {
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
        guard !hiddenForCapture,
              statusOverlay == nil else {
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

        if statusOverlay == nil {
            drawDimmedBackground()
        } else {
            NSColor.clear.setFill()
            dirtyRect.fill(using: .clear)
        }

        if let selectionRect {
            if statusOverlay == nil {
                drawUndimmedBackground(in: selectionRect)
            }

            NSColor.white.withAlphaComponent(0.95).setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 1
            path.stroke()

            if let statusOverlay {
                drawStatusOverlay(statusOverlay, around: selectionRect)
                return
            }

            drawSelectionHandles(in: selectionRect)
            drawSizeBadge(for: selectionRect)
            if behavior == .capture,
               toolbarCaptureMode == .screenshot {
                drawAnnotations(in: selectionRect)
            }
        } else if let autoSelectionCandidateRect {
            drawUndimmedBackground(in: autoSelectionCandidateRect)
            drawAutoSelectionCandidate(autoSelectionCandidateRect)
        }
    }

    private func drawDimmedBackground() {
        if !drawFullInitialSnapshotIfNeeded() {
            NSColor.black.withAlphaComponent(0.32).setFill()
            bounds.fill()
        }
    }

    private func drawFullInitialSnapshotIfNeeded() -> Bool {
        guard let initialSnapshot,
              let croppedImage = initialSnapshot.croppedImage(in: screenFrame) else {
            return false
        }

        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: croppedImage, size: bounds.size).draw(
            in: bounds,
            from: CGRect(origin: .zero, size: bounds.size),
            operation: .sourceOver,
            fraction: 1
        )

        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        return true
    }

    private func drawUndimmedBackground(in rect: CGRect) {
        if let initialSnapshot {
            drawInitialSnapshot(initialSnapshot, in: rect)
        } else {
            NSColor.clear.setFill()
            rect.fill(using: .clear)
        }

        drawBaseImage(in: rect)
    }

    func prepareForCapture() {
        hiddenForCapture = true
        statusOverlay = nil
        closeTransientUI()
        needsDisplay = true
    }

    func beginScrollingCaptureProgress(
        finish: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        hiddenForCapture = false
        statusOverlay = .scrollingCapture(finish: finish, cancel: cancel)
        interaction = .idle
        closeTransientUI()
        autoSelectionCandidateRect = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
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
        if statusOverlay == nil {
            hideStatusControl()
        }
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
        if behavior == .capture,
           toolbarCaptureMode == .screenshot,
           annotation(at: point, in: selectionRect) != nil {
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
        guard behavior == .capture,
              toolbarCaptureMode == .screenshot else {
            return
        }

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
        field.placeholderString = L10n.captureToolText
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
        guard behavior == .capture else {
            clearBaseImage()
            return
        }

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

        if let initialSnapshot,
           let snapshotData = try? initialSnapshot.pngData(in: screenRect) {
            setBaseImageData(snapshotData, for: screenRect)
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

    private func drawInitialSnapshot(_ snapshot: ScreenCaptureSnapshot, in selectionRect: CGRect) {
        guard let croppedImage = snapshot.croppedImage(in: screenRect(fromLocalRect: selectionRect)) else {
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: croppedImage, size: selectionRect.size).draw(
            in: selectionRect,
            from: CGRect(origin: .zero, size: selectionRect.size),
            operation: .sourceOver,
            fraction: 1
        )
    }

    private var shouldDrawCapturedBaseImage: Bool {
        switch behavior {
        case .capture:
            guard toolbarCaptureMode == .screenshot else {
                return false
            }

            return annotationStore.annotations.contains { annotation in
                annotation.kind == .mosaic
            }
        case .selectRegion:
            return false
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
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        path.fill()
        drawSizeBadge(for: rect)
    }

    private func drawStatusOverlay(_ status: RegionSelectionStatusOverlay, around rect: CGRect) {
        switch status {
        case .scrollingCapture:
            drawScrollingCaptureStatus(around: rect)
        }
    }

    private func drawScrollingCaptureStatus(around rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()
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
        if behavior == .selectRegion {
            showSelectionConfirmToolbarIfNeeded()
            return
        }

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

    private func showSelectionConfirmToolbarIfNeeded() {
        guard let selectionRect,
              toolbarWindow == nil else {
            positionToolbar()
            return
        }

        let toolbarView = RegionSelectionConfirmToolbarView(
            startAction: actions.finishSelection,
            cancelAction: actions.cancel
        )
        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 220, height: 44)
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

    private func showStatusControl(for status: RegionSelectionStatusOverlay) {
        guard let selectionRect else {
            return
        }

        let statusView: RegionSelectionStatusControlView
        switch status {
        case .scrollingCapture(let finish, let cancel):
            statusView = RegionSelectionStatusControlView(
                title: L10n.pixScrollingCaptureInProgress,
                finishHelp: L10n.pixScrollingCaptureFinishHelp,
                cancelHelp: L10n.pixScrollingCaptureCancelHelp,
                finishAction: finish,
                cancelAction: cancel
            )
        }

        let hostingView = NSHostingView(rootView: statusView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(fittingSize.width, 1),
            height: max(fittingSize.height, 1)
        )

        let statusWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        statusWindow.contentView = hostingView
        statusWindow.backgroundColor = .clear
        statusWindow.isOpaque = false
        statusWindow.level = .screenSaver
        statusWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        statusWindow.ignoresMouseEvents = false
        statusWindow.isReleasedWhenClosed = false
        statusWindow.orderFront(nil)
        self.statusWindow = statusWindow

        _ = selectionRect
        positionStatusControl()
    }

    private func positionStatusControl() {
        guard let statusWindow,
              let selectionRect else {
            return
        }

        let statusSize = statusWindow.frame.size
        let screenRect = screenRect(fromLocalRect: selectionRect)
        let padding: CGFloat = 10
        var origin = CGPoint(
            x: screenRect.midX - statusSize.width / 2,
            y: screenRect.minY - statusSize.height - padding
        )

        if origin.y < screenFrame.minY + padding {
            origin.y = screenRect.maxY + padding
        }

        origin.x = min(
            max(origin.x, screenFrame.minX + padding),
            screenFrame.maxX - statusSize.width - padding
        )
        origin.y = min(
            max(origin.y, screenFrame.minY + padding),
            screenFrame.maxY - statusSize.height - padding
        )

        statusWindow.setFrameOrigin(origin)
    }

    private func hideStatusControl() {
        statusWindow?.orderOut(nil)
        statusWindow?.close()
        statusWindow = nil
    }

    private func refreshToolbar() {
        guard behavior == .capture else {
            positionToolbar()
            return
        }

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
            captureMode: toolbarCaptureMode,
            activeTool: activeTool,
            activeStyle: activeStyle,
            canUndo: annotationStore.canUndo,
            canRedo: annotationStore.canRedo
        )
    }

    private var toolbarActions: RegionToolbarActions {
        RegionToolbarActions(
            setCaptureMode: { [weak self] mode in
                self?.setToolbarCaptureMode(mode)
            },
            setTool: { [weak self] tool in
                self?.commitTextEditor()
                self?.toolbarCaptureMode = .screenshot
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
            recognizeText: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.recognizeText)
            },
            scrollingCapture: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.scrollingCapture)
            },
            cancel: { [weak self] in
                self?.actions.cancel()
            },
            finish: { [weak self] in
                self?.finishPrimaryToolbarAction()
            },
            startRecording: { [weak self] in
                self?.commitTextEditor()
                self?.actions.finish(.startRecording)
            }
        )
    }

    private func setToolbarCaptureMode(_ mode: ScreenshotRegionCaptureMode) {
        commitTextEditor()
        toolbarCaptureMode = mode
        if mode == .recording {
            activeTool = nil
            clearBaseImage()
        }
        refreshToolbar()
        needsDisplay = true
        actions.setNeedsDisplayOnAllScreens()
        window?.invalidateCursorRects(for: self)
    }

    private func finishPrimaryToolbarAction() {
        commitTextEditor()
        switch toolbarCaptureMode {
        case .screenshot:
            actions.finish(.copy)
        case .recording:
            actions.finish(.startRecording)
        }
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
            x: screenRect.maxX - toolbarSize.width,
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

private extension [ScreenCaptureSnapshot] {
    func bestSnapshot(for screenFrame: CGRect) -> ScreenCaptureSnapshot? {
        guard let snapshot = self.max(by: { first, second in
            first.screenFrame.intersection(screenFrame).area < second.screenFrame.intersection(screenFrame).area
        }),
        snapshot.screenFrame.intersection(screenFrame).area > 0 else {
            return nil
        }

        return snapshot
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
            primaryToolbar

            if state.captureMode == .screenshot {
                secondaryToolbar
                    .buttonStyle(.borderless)
                    .toolbarSurface()
                    .transition(.opacity)
            }
        }
        // 预留悬停提示的绘制空间:选区工具栏运行在透明无边框窗口中,
        // 提示气泡以 overlay 形式绘制在按钮下方,需要窗口在布局上预留高度,
        // 否则会落在窗口边界外而不可见。
        .padding(.bottom, 32)
        .fixedSize()
    }

    private var primaryToolbar: some View {
        HStack(spacing: 6) {
            Picker(L10n.captureMode, selection: Binding(
                get: { state.captureMode },
                set: actions.setCaptureMode
            )) {
                ForEach(ScreenshotRegionCaptureMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .tag(mode)
                        .help(mode.title)
                        .accessibilityLabel(mode.title)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 72)

            Divider()
                .frame(height: 22)

            switch state.captureMode {
            case .screenshot:
                screenshotToolbarItems
            case .recording:
                recordingToolbarItems
            }
        }
        .buttonStyle(.borderless)
        .toolbarSurface()
    }

    private var screenshotToolbarItems: some View {
        Group {
            toolButton(nil, symbolName: "hand.draw", title: L10n.captureToolMove)

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
            .hoverTooltip(L10n.captureUndo)

            Button(action: actions.redo) {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 22, height: 22)
            }
            .disabled(!state.canRedo)
            .hoverTooltip(L10n.captureRedo)

            Button(action: actions.pin) {
                Image(systemName: "pin")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonPinToScreen)

            Button(action: actions.recognizeText) {
                Image(systemName: "doc.text.viewfinder")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.pixOCRTool)

            Button(action: actions.scrollingCapture) {
                Image(systemName: "arrow.down.doc")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.pixScrollingCaptureTool)

            Button(action: actions.save) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonSave)

            Button(action: actions.cancel) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonCancel)

            Button(action: actions.finish) {
                Image(systemName: "checkmark")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonDone)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var recordingToolbarItems: some View {
        Group {
            Button(action: actions.cancel) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonCancel)

            Button(action: actions.startRecording) {
                Label(L10n.captureStartRecording, systemImage: "record.circle")
            }
            .hoverTooltip(L10n.captureStartRecording)
            .keyboardShortcut(.return, modifiers: [])
        }
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
                action: actions.setLineWidth,
                help: L10n.captureLineWidth
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
                action: actions.setFontSize,
                help: L10n.captureFontSize
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
            .hoverTooltip(L10n.captureMosaicMode)

            Divider().frame(height: 22)

            sizeDots(
                values: [8, 14, 22, 32],
                selected: state.activeStyle.mosaicBlockSize,
                action: actions.setMosaicBlockSize,
                help: L10n.captureMosaicBlockSize
            )

            if state.activeStyle.mosaicMode == .brush {
                Divider().frame(height: 22)
                sizeDots(
                    values: [16, 28, 44],
                    selected: state.activeStyle.mosaicBrushSize,
                    action: actions.setMosaicBrushSize,
                    help: L10n.captureMosaicBrushSize
                )
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
                .hoverTooltip(L10n.captureColor)
            }
        }
    }

    private func sizeDots(
        values: [CGFloat],
        selected: CGFloat,
        action: @escaping (CGFloat) -> Void,
        help: String? = nil
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
                .hoverTooltip(help ?? "")
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
        .hoverTooltip(title)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(tool == state.activeTool ? Color.accentColor.opacity(0.18) : .clear)
        )
    }
}

private struct RegionSelectionConfirmToolbarView: View {
    let startAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: cancelAction) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(L10n.commonCancel)

            Button(action: startAction) {
                Label(L10n.captureStartRecording, systemImage: "record.circle")
            }
            .keyboardShortcut(.return, modifiers: [])
            .hoverTooltip(L10n.captureStartRecording)
        }
        .buttonStyle(.borderless)
        .toolbarSurface()
        .padding(.bottom, 32)
        .fixedSize()
    }
}

private struct RegionSelectionStatusControlView: View {
    let title: String
    let finishHelp: String
    let cancelHelp: String
    let finishAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button(action: finishAction) {
                Image(systemName: "checkmark")
                    .frame(width: 22, height: 22)
            }
            .keyboardShortcut(.return, modifiers: [])
            .hoverTooltip(finishHelp)

            Button(action: cancelAction) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .hoverTooltip(cancelHelp)
        }
        .buttonStyle(.borderless)
        .toolbarSurface()
        .padding(.bottom, 32)
        .fixedSize()
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

    /// 自绘悬停提示。
    ///
    /// 选区工具栏运行在透明无边框 `NSPanel` 中,系统的 `.help()` tooltip 在这种窗口里
    /// 不会显示,因此这里用 SwiftUI overlay 在同一窗口内绘制提示气泡。
    func hoverTooltip(_ text: String) -> some View {
        modifier(RegionSelectionHoverTooltip(text: text))
    }
}

/// 在控件上方显示提示气泡,鼠标悬停时出现。
private struct RegionSelectionHoverTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                hoverTask?.cancel()
                if hovering {
                    // 轻微延迟,避免鼠标快速划过时闪烁。
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        isHovering = true
                    }
                } else {
                    isHovering = false
                }
            }
            .overlay(alignment: .bottom) {
                if isHovering {
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.black.opacity(0.86))
                        )
                        .foregroundStyle(.white)
                        .fixedSize()
                        .offset(y: 30)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.12), value: isHovering)
                        .allowsHitTesting(false)
                }
            }
    }
}
