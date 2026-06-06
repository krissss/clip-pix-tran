import CoreGraphics
import Testing
@testable import ClipPixTran

@MainActor
struct ScreenshotAnnotationStoreTests {
    @Test func appendSupportsUndoAndRedo() {
        let store = ScreenshotAnnotationStore()
        let annotation = ScreenshotAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)],
            style: ScreenshotAnnotationStyle()
        )

        store.append(annotation)

        #expect(store.annotations == [annotation])
        #expect(store.canUndo)
        #expect(!store.canRedo)

        store.undo()

        #expect(store.annotations.isEmpty)
        #expect(!store.canUndo)
        #expect(store.canRedo)

        store.redo()

        #expect(store.annotations == [annotation])
        #expect(store.canUndo)
        #expect(!store.canRedo)
    }

    @Test func replacingLastAnnotationDoesNotAddUndoStep() {
        let store = ScreenshotAnnotationStore()
        let first = ScreenshotAnnotation(
            kind: .arrow,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)],
            style: ScreenshotAnnotationStyle()
        )
        var updated = first
        updated.points[1] = CGPoint(x: 40, y: 40)

        store.append(first)
        store.replaceLast(with: updated)
        store.undo()

        #expect(store.annotations.isEmpty)
    }

    @Test func discardLatestChangeRestoresPreviousSnapshot() {
        let store = ScreenshotAnnotationStore()
        let annotation = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 8, y: 8), CGPoint(x: 8, y: 8)],
            style: ScreenshotAnnotationStyle(),
            text: ""
        )

        store.append(annotation)
        store.discardLatestChange()

        #expect(store.annotations.isEmpty)
        #expect(!store.canUndo)
        #expect(!store.canRedo)
    }

    @Test func replacingByIDAfterPreparedMutationSupportsUndo() {
        let store = ScreenshotAnnotationStore()
        let annotation = ScreenshotAnnotation(
            kind: .text,
            points: [CGPoint(x: 8, y: 8)],
            style: ScreenshotAnnotationStyle(),
            text: "Pix"
        )
        let moved = annotation.translated(by: CGSize(width: 20, height: 12))

        store.append(annotation)
        store.prepareUndoForMutation()
        store.replace(id: annotation.id, with: moved)

        #expect(store.annotations == [moved])

        store.undo()

        #expect(store.annotations == [annotation])
    }

    @Test func resetClearsAnnotationsAndUndoHistory() {
        let store = ScreenshotAnnotationStore()
        let annotation = ScreenshotAnnotation(
            kind: .rectangle,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)],
            style: ScreenshotAnnotationStyle()
        )

        store.append(annotation)
        store.reset()
        store.undo()

        #expect(store.annotations.isEmpty)
        #expect(!store.canUndo)
        #expect(!store.canRedo)
    }
}
