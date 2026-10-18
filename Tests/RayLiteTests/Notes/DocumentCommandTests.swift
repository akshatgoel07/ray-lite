import AppKit
import Testing
@testable import RayLite

@MainActor
struct NoteCommandTests {
    private func window(_ canvas: BoardSurface) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.loadNotes()
        return window
    }

    @Test func deleteUndoRedoPreservesRecordsAndOrder() throws {
        let store = NoteStore(inMemory: true)
        let records = [3, 7, 11].map { order in
            NoteRecord(id: UUID(), text: "Note \(order)\n\nMore text.",
                       frame: CGRect(x: order * 23, y: -order * 13, width: 210 + order, height: 170), order: order)
        }
        for record in records { try store.insert(record).get() }
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        let manager = try #require(window.undoManager)
        canvas.select([records[0].id, records[2].id])
        canvas.delete(nil)
        #expect(canvas.notes == [records[1]])
        #expect(try store.load().get() == canvas.notes)
        manager.undo()
        #expect(canvas.notes == records)
        #expect(try store.load().get() == records)
        #expect(canvas.entryTiles.map(\.id) == records.map(\.id))
        #expect(canvas.selection == [records[0].id, records[2].id])
        for view in canvas.entryTiles {
            #expect(view.layer?.opacity == 1)
            #expect(view.layer?.animation(forKey: "rayLite.noteFade") == nil)
        }
        #expect(!manager.canUndo)
        manager.redo()
        #expect(canvas.notes == [records[1]])
        #expect(try store.load().get() == canvas.notes)
        manager.undo()
        #expect(canvas.notes == records)
    }

    @Test func createEditAndMoveEachUseOneUndoStep() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        let manager = try #require(window.undoManager)
        let note = try #require(canvas.newNote())
        #expect(canvas.finishEditing())
        #expect(canvas.updateText(id: note.id, text: "First paragraph.\n\nSecond paragraph."))
        let edited = canvas.notes
        let moved = note.frame.offsetBy(dx: 80, dy: -35)
        canvas.previewFrames([note.id: moved])
        canvas.commitFrames(from: [note.id: note.frame], actionName: "Move Notes")
        #expect(manager.groupingLevel == 0)
        #expect(canvas.notes.first?.frame == moved)
        manager.undo()
        #expect(canvas.notes == edited)
        manager.undo()
        #expect(canvas.notes == [note])
        manager.undo()
        #expect(canvas.notes.isEmpty)
        #expect(try store.load().get().isEmpty)
        #expect(!manager.canUndo)
        manager.redo()
        manager.redo()
        manager.redo()
        #expect(canvas.notes.first?.frame == moved)
        #expect(canvas.notes.first?.text == edited.first?.text)
        #expect(try store.load().get() == canvas.notes)
        #expect(!manager.canRedo)
    }

    @Test func spacesKeepNotesSeparateAndUndoReturnsToTheCorrectBoard() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        let manager = try #require(window.undoManager)
        let firstNote = try #require(canvas.newNote())
        #expect(canvas.finishEditing())
        let second = try #require(canvas.newSpace())
        #expect(second.name == "Space02")
        #expect(canvas.currentSpaceID == second.id)
        #expect(canvas.notes.isEmpty)
        #expect(canvas.selection.isEmpty)
        #expect(canvas.entryTiles.isEmpty)
        let secondNote = try #require(canvas.newNote())
        #expect(canvas.finishEditing())
        #expect(secondNote.spaceID == second.id)
        #expect(canvas.switchSpace(SpaceRecord.firstID))
        #expect(canvas.notes == [firstNote])
        manager.undo()
        #expect(canvas.currentSpaceID == second.id)
        #expect(canvas.notes.isEmpty)
        #expect(try store.load(spaceID: SpaceRecord.firstID).get() == [firstNote])
        manager.undo()
        #expect(canvas.spaces.count == 1)
        #expect(canvas.currentSpaceID == SpaceRecord.firstID)
        #expect(canvas.notes == [firstNote])
        manager.redo()
        #expect(canvas.currentSpaceID == second.id)
        #expect(canvas.spaces.map(\.name) == ["Space01", "Space02"])
        manager.redo()
        #expect(canvas.notes == [secondNote])
        #expect(try store.load(spaceID: second.id).get() == [secondNote])
        #expect(canvas.newSpace()?.name == "Space03")
    }

    @Test func spaceUndoPreservesAnOccupiedBoard() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        let space = try #require(canvas.newSpace())
        let note = NoteRecord(id: UUID(), text: "Keep this note", frame: .zero, order: 0, spaceID: space.id)
        try store.insert(note).get()
        window.undoManager?.undo()
        #expect(try store.loadSpaces().get().contains(space))
        #expect(try store.load(spaceID: space.id).get() == [note])
    }

    @Test func unchangedEditAndFrameDoNotAddUndo() throws {
        let store = NoteStore(inMemory: true)
        let note = NoteRecord(id: UUID(), text: "Saved", frame: CGRect(x: 0, y: 0, width: 240, height: 150), order: 0)
        try store.insert(note).get()
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        #expect(canvas.updateText(id: note.id, text: note.text))
        canvas.commitFrames(from: [note.id: note.frame], actionName: "Move Notes")
        #expect(window.undoManager?.canUndo == false)
        #expect(canvas.notes == [note])
    }

    @Test func failedChangesKeepSavedModelAndDoNotAddUndo() throws {
        let store = NoteStore(inMemory: true)
        let note = NoteRecord(id: UUID(), text: "Saved", frame: CGRect(x: 0, y: 0, width: 240, height: 150), order: 0)
        try store.insert(note).get()
        let canvas = BoardSurface(store: store)
        let window = window(canvas)
        defer { window.contentView = nil }
        try store.delete(id: note.id).get()
        #expect(!canvas.updateText(id: note.id, text: "Unsaved"))
        #expect(canvas.saveError == NoteStoreError.missingID(note.id).message)
        #expect(canvas.notes == [note])
        canvas.previewFrames([note.id: note.frame.offsetBy(dx: 40, dy: 20)])
        canvas.commitFrames(from: [note.id: note.frame], actionName: "Move Notes")
        #expect(canvas.notes == [note])
        #expect(canvas.entryTiles.first?.frame == note.frame)
        #expect(window.undoManager?.canUndo == false)
        canvas.dismissSaveError(nil)
        #expect(canvas.saveError == nil)
    }

}
