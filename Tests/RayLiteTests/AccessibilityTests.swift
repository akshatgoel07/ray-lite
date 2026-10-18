import AppKit
import Testing
@testable import RayLite

@MainActor
struct AccessibilityTests {
    @Test func noteElementsFollowModelTextSelectionAndDeletion() throws {
        let canvas = CanvasView(store: NoteStore(inMemory: true))
        canvas.frame = CGRect(x: 0, y: 0, width: 1080, height: 720)
        canvas.loadNotes()
        let first = try #require(canvas.newNote())
        let second = try #require(canvas.newNote())
        let elements = try #require(canvas.accessibilityChildren() as? [NoteAccessibilityElement])
        #expect(elements.map(\.id) == [first.id, second.id])
        #expect(elements.allSatisfy { $0.accessibilityRole() == .group })
        #expect(elements.allSatisfy { $0.accessibilityParent() as? CanvasView === canvas })
        #expect(!elements[1].isAccessibilitySelected())
        #expect(canvas.accessibilityValue() as? String == "No selected notes")
        #expect(canvas.updateText(id: first.id, text: "First note text"))
        #expect(elements[0].accessibilityLabel() == "First note text")
        #expect(elements[0].accessibilityValue() as? String == "First note text")
        #expect(elements[0].accessibilityPerformPress())
        #expect(canvas.selection == [first.id])
        #expect(canvas.accessibilityValue() as? String == "First note text")
        #expect((canvas.accessibilityChildren()?.first as? NoteAccessibilityElement) === elements[0])
        canvas.delete(nil)
        #expect(canvas.accessibilityChildren()?.count == 1)
        #expect(elements[0].accessibilityLabel() == nil)
        #expect(!elements[0].accessibilityPerformPress())
        #expect(!elements[0].accessibilityPerformPick())
        #expect(canvas.accessibilityValue() as? String == "No selected notes")
    }
}
