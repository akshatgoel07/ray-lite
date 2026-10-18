import AppKit

@MainActor
public enum UnboxingSequence {
    static func sampleNotes(center: CGPoint, order: Int) -> [NoteRecord] {
        [
            NoteRecord(id: UUID(), text: "A place for your ideas.",
                       frame: CGRect(x: center.x - 226, y: center.y - 58, width: 212, height: 116),
                       order: order),
            NoteRecord(id: UUID(), text: """
                       A note can hold several paragraphs. The text wraps within the card at its real size.

                       Keep ideas, plans, and useful details together. Resize the window and the note keeps the same size and text.

                       Add another note when you need more space.
                       """,
                       frame: CGRect(x: center.x + 14, y: center.y - 121, width: 212, height: 242),
                       order: order + 1)
        ]
    }
}
