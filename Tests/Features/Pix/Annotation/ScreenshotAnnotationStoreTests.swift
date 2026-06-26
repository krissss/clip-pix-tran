import CoreGraphics
import Foundation
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

    @Test func removingStepAnnotationRenumbersRemainingStepsAndSupportsUndo() {
        let store = ScreenshotAnnotationStore()
        let first = ScreenshotAnnotation(
            kind: .step,
            points: [CGPoint(x: 8, y: 8)],
            style: ScreenshotAnnotationStyle(),
            text: "First"
        )
        let second = ScreenshotAnnotation(
            kind: .step,
            points: [CGPoint(x: 18, y: 18)],
            style: ScreenshotAnnotationStyle(),
            text: "Second"
        )
        let third = ScreenshotAnnotation(
            kind: .step,
            points: [CGPoint(x: 28, y: 28)],
            style: ScreenshotAnnotationStyle(),
            text: "Third"
        )

        store.append(first)
        store.append(second)
        store.append(third)

        #expect(store.stepNumber(for: first.id) == 1)
        #expect(store.stepNumber(for: second.id) == 2)
        #expect(store.stepNumber(for: third.id) == 3)

        store.remove(id: second.id)

        #expect(store.annotations == [first, third])
        #expect(store.stepNumber(for: first.id) == 1)
        #expect(store.stepNumber(for: second.id) == nil)
        #expect(store.stepNumber(for: third.id) == 2)

        store.undo()

        #expect(store.annotations == [first, second, third])
        #expect(store.stepNumber(for: second.id) == 2)
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

    @Test func styleDecodesLegacyPayloadWithoutFontWeight() throws {
        let data = Data(
            """
            {
              "colorComponents": {
                "red": 0.94,
                "green": 0.2,
                "blue": 0.2,
                "alpha": 1
              },
              "lineWidth": 3,
              "fontSize": 20,
              "mosaicMode": "rectangle",
              "mosaicBlockSize": 14,
              "mosaicBrushSize": 28
            }
            """.utf8
        )

        let style = try JSONDecoder().decode(ScreenshotAnnotationStyle.self, from: data)

        #expect(style.fontWeight == .medium)
    }
}
