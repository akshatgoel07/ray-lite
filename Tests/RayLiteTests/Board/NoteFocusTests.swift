import AppKit
import Foundation
import Testing
@testable import RayLite

@MainActor
struct BoardNoteFocusTests {
    @Test func loadPreservesReferenceCardBounds() throws {
        let store = NoteStore(inMemory: true)
        let note = NoteRecord(id: UUID(), text: "Personal rebranding\nA place for ideas.",
                              frame: CGRect(x: 242, y: 501, width: 141, height: 200), order: 0)
        try store.insert(note).get()
        let canvas = BoardSurface(store: store)
        canvas.loadNotes()
        #expect(canvas.notes == [note])
        #expect(try store.load().get() == [note])
    }

    @Test func longPreviewClipsWithinOriginalBounds() {
        let frame = CGRect(x: 20, y: 40, width: 141, height: 200)
        let text = "Ideas\n" + Array(repeating: "A place for ideas.", count: 400).joined(separator: "\n")
        let fitted = NoteTextLayer.fittedFrame(frame, text: text)
        #expect(fitted.width == frame.width)
        #expect(fitted.maxY == frame.maxY)
        #expect(fitted.height == frame.height)
        #expect(NoteTextLayer.fittedFrame(fitted, text: text) == fitted)
    }

    @Test func newNoteUsesVisibleCenterAndPreservesModelGeometry() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 520, height: 380)
        canvas.loadNotes()
        canvas.panBy(CGSize(width: 80, height: -40))
        canvas.layoutSubtreeIfNeeded()
        let center = canvas.canvasPoint(from: CGPoint(x: 259, y: 200))
        let note = try #require(canvas.newNote())
        #expect(note.frame.midX == center.x)
        #expect(note.frame.midY == center.y)
        #expect(canvas.selection.isEmpty)
        #expect(note.frame.size == CGSize(width: 140, height: 200))
        #expect(note.text.isEmpty)
        let view = try #require(canvas.entryTiles.first)
        view.frame = CGRect(x: -30, y: 70, width: 310, height: 210)
        #expect(canvas.notes.first?.frame == view.frame)
        #expect(view.entryDescriptor.id == note.id)
        #expect(view.entryDescriptor.size == view.frame.size)
        canvas.commitItemFrames()
        #expect(try store.load().get().first?.frame == view.frame)
    }

    @Test func windowResizeKeepsTheVisibleCenterWithoutNoteChanges() throws {
        let canvas = BoardSurface(store: NoteStore(inMemory: true))
        canvas.frame = CGRect(x: 0, y: 0, width: 1080, height: 720)
        canvas.layoutSubtreeIfNeeded()
        canvas.loadNotes()
        let note = try #require(canvas.newNote())
        let center = canvas.canvasPoint(from: CGPoint(x: 540, y: 360))
        canvas.frame.size = CGSize(width: 520, height: 380)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.canvasPoint(from: CGPoint(x: 260, y: 190)) == center)
        #expect(canvas.notes.first == note)
        #expect(canvas.viewPoint(from: CGPoint(x: note.frame.midX, y: note.frame.midY)) == CGPoint(x: 259, y: 200))
    }

    @Test func failedLoadBlocksCreationUntilRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.sqlite")
        let corrupt = Data("Invalid note store".utf8)
        try corrupt.write(to: url)
        let canvas = BoardSurface(store: NoteStore(storeURL: url))
        canvas.loadNotes()
        guard case .loadError = canvas.loadState else {
            Issue.record("A corrupt store must produce a load error.")
            return
        }
        #expect(canvas.newNote() == nil)
        canvas.addSampleNotes()
        #expect(canvas.notes.isEmpty)
        #expect(try Data(contentsOf: url) == corrupt)
        try FileManager.default.removeItem(at: url)
        canvas.loadNotes()
        guard case .empty = canvas.loadState else {
            Issue.record("Retry must load the repaired store.")
            return
        }
        #expect(canvas.newNote() != nil)
    }

    @Test func explicitSamplesSurviveReloadWithoutDuplicates() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        canvas.frame = CGRect(x: 0, y: 0, width: 520, height: 380)
        canvas.loadNotes()
        #expect(canvas.notes.isEmpty)
        canvas.addSampleNotes()
        let samples = canvas.notes
        #expect(samples.count == 2)
        #expect(samples[0].text == "A place for your ideas.")
        #expect(samples[1].text.contains("\n\n"))
        canvas.loadNotes()
        #expect(canvas.notes == samples)
        let restart = BoardSurface(store: store)
        restart.loadNotes()
        #expect(restart.notes == samples)
        #expect(restart.entryTiles.map { $0.entryDescriptor.id } == samples.map(\.id))
    }
}
