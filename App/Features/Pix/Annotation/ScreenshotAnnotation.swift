import AppKit

enum ScreenshotAnnotationKind: String, Codable, Equatable, Sendable {
    case rectangle
    case ellipse
    case arrow
    case pen
    case text
    case mosaic
    case step
}

enum ScreenshotMosaicMode: String, Codable, Equatable, Sendable {
    case rectangle
    case brush
}

enum ScreenshotTextWeight: String, Codable, Equatable, Sendable {
    case regular
    case medium
    case bold
}

struct ScreenshotAnnotationStyle: Codable, Equatable, Sendable {
    var colorComponents: ScreenshotColorComponents
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var fontWeight: ScreenshotTextWeight
    var mosaicMode: ScreenshotMosaicMode
    var mosaicBlockSize: CGFloat
    var mosaicBrushSize: CGFloat

    init(
        colorComponents: ScreenshotColorComponents = .red,
        lineWidth: CGFloat = 3,
        fontSize: CGFloat = 20,
        fontWeight: ScreenshotTextWeight = .medium,
        mosaicMode: ScreenshotMosaicMode = .rectangle,
        mosaicBlockSize: CGFloat = 14,
        mosaicBrushSize: CGFloat = 28
    ) {
        self.colorComponents = colorComponents
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.mosaicMode = mosaicMode
        self.mosaicBlockSize = mosaicBlockSize
        self.mosaicBrushSize = mosaicBrushSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        colorComponents = try container.decode(ScreenshotColorComponents.self, forKey: .colorComponents)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        fontWeight = try container.decodeIfPresent(ScreenshotTextWeight.self, forKey: .fontWeight) ?? .medium
        mosaicMode = try container.decode(ScreenshotMosaicMode.self, forKey: .mosaicMode)
        mosaicBlockSize = try container.decode(CGFloat.self, forKey: .mosaicBlockSize)
        mosaicBrushSize = try container.decode(CGFloat.self, forKey: .mosaicBrushSize)
    }

    @MainActor
    var nsColor: NSColor {
        colorComponents.nsColor
    }
}

struct ScreenshotColorComponents: Codable, Equatable, Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    @MainActor
    var nsColor: NSColor {
        NSColor(
            calibratedRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    static let red = ScreenshotColorComponents(red: 0.94, green: 0.20, blue: 0.20)
    static let orange = ScreenshotColorComponents(red: 0.96, green: 0.45, blue: 0.12)
    static let yellow = ScreenshotColorComponents(red: 0.93, green: 0.74, blue: 0.16)
    static let green = ScreenshotColorComponents(red: 0.16, green: 0.72, blue: 0.43)
    static let blue = ScreenshotColorComponents(red: 0.17, green: 0.48, blue: 0.94)
    static let purple = ScreenshotColorComponents(red: 0.58, green: 0.36, blue: 0.92)
    static let white = ScreenshotColorComponents(red: 1, green: 1, blue: 1)
    static let black = ScreenshotColorComponents(red: 0.08, green: 0.09, blue: 0.11)
}

struct ScreenshotAnnotation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ScreenshotAnnotationKind
    var points: [CGPoint]
    var style: ScreenshotAnnotationStyle
    var text: String?

    init(
        id: UUID = UUID(),
        kind: ScreenshotAnnotationKind,
        points: [CGPoint],
        style: ScreenshotAnnotationStyle,
        text: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.style = style
        self.text = text
    }

    nonisolated var rect: CGRect {
        guard let first = points.first else {
            return .null
        }

        return points.dropFirst().reduce(
            CGRect(origin: first, size: .zero)
        ) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }.standardized
    }

    nonisolated func translated(by offset: CGSize) -> ScreenshotAnnotation {
        var translated = self
        translated.points = points.map { point in
            CGPoint(
                x: point.x + offset.width,
                y: point.y + offset.height
            )
        }
        return translated
    }
}

@MainActor
@Observable
final class ScreenshotAnnotationStore {
    private(set) var annotations: [ScreenshotAnnotation] = []
    private(set) var canUndo = false
    private(set) var canRedo = false

    private var undoStack: [[ScreenshotAnnotation]] = []
    private var redoStack: [[ScreenshotAnnotation]] = []

    func append(_ annotation: ScreenshotAnnotation) {
        guard !annotation.points.isEmpty else {
            return
        }

        pushUndoSnapshot()
        annotations.append(annotation)
        redoStack.removeAll()
        refreshAvailability()
    }

    func replaceLast(with annotation: ScreenshotAnnotation) {
        guard !annotations.isEmpty else {
            append(annotation)
            return
        }

        annotations[annotations.count - 1] = annotation
        refreshAvailability()
    }

    func prepareUndoForMutation() {
        pushUndoSnapshot()
        redoStack.removeAll()
        refreshAvailability()
    }

    func replace(id: UUID, with annotation: ScreenshotAnnotation) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        annotations[index] = annotation
        refreshAvailability()
    }

    func remove(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        pushUndoSnapshot()
        annotations.remove(at: index)
        redoStack.removeAll()
        refreshAvailability()
    }

    func stepNumber(for id: UUID) -> Int? {
        var stepNumber = 0
        for annotation in annotations where annotation.kind == .step {
            stepNumber += 1
            if annotation.id == id {
                return stepNumber
            }
        }
        return nil
    }

    func removeLastIfEmpty() {
        guard let last = annotations.last,
              last.points.isEmpty || last.rect.isNull else {
            return
        }

        annotations.removeLast()
        refreshAvailability()
    }

    func discardLatestChange() {
        guard let previous = undoStack.popLast() else {
            return
        }

        annotations = previous
        redoStack.removeAll()
        refreshAvailability()
    }

    func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }

        redoStack.append(annotations)
        annotations = previous
        refreshAvailability()
    }

    func redo() {
        guard let next = redoStack.popLast() else {
            return
        }

        undoStack.append(annotations)
        annotations = next
        refreshAvailability()
    }

    func clear() {
        guard !annotations.isEmpty else {
            return
        }

        pushUndoSnapshot()
        annotations.removeAll()
        redoStack.removeAll()
        refreshAvailability()
    }

    func reset() {
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        refreshAvailability()
    }

    private func pushUndoSnapshot() {
        undoStack.append(annotations)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
    }

    private func refreshAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
