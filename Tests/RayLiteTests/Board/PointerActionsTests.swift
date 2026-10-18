import AppKit
import Testing
@testable import RayLite

struct GestureTests {
    private func note(_ x: CGFloat = 100, _ y: CGFloat = 100, order: Int = 0) -> NoteRecord {
        NoteRecord(id: UUID(), text: "Note", frame: CGRect(x: x, y: y, width: 240, height: 150), order: order)
    }

    @Test func clickUsesTopNoteAndPreservesSelectedGroup() {
        let first = note()
        let top = note(order: 1)
        let other = note(500)
        let notes = [first, other, top]
        var gesture = PointerGesture()
        let point = CGPoint(x: 170, y: 170)
        #expect(gesture.press(at: point, viewport: Viewport(), notes: notes, selection: []).selection == [top.id])
        #expect(gesture.state.name == "pressed")
        #expect(gesture.end() == nil)
        #expect(gesture.state.name == "idle")
        #expect(gesture.press(at: point, viewport: Viewport(), notes: notes,
                              selection: [top.id, other.id]).selection == [top.id, other.id])
        #expect(gesture.press(at: point, viewport: Viewport(), notes: notes,
                              selection: [first.id, other.id]).selection == [top.id])
        #expect(gesture.press(at: point, viewport: Viewport(), notes: notes,
                              selection: [top.id, other.id], shift: true).selection == [other.id])
        #expect(gesture.press(at: point, viewport: Viewport(), notes: notes,
                              selection: [other.id], shift: true).selection == [top.id, other.id])
        #expect(gesture.press(at: .zero, viewport: Viewport(), notes: notes,
                              selection: [top.id]).selection == [])
    }

    @Test(arguments: [false, true])
    func releaseOpensSelectedAndUnselectedCards(selected: Bool) {
        let item = note()
        var gesture = PointerGesture()
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        _ = gesture.press(at: start, viewport: Viewport(), notes: [item],
                          selection: selected ? [item.id] : [])
        #expect(gesture.clickedItem == item.id)
        _ = gesture.move(to: CGPoint(x: start.x + 2, y: start.y))
        #expect(gesture.clickedItem == item.id)
        _ = gesture.move(to: CGPoint(x: start.x + 30, y: start.y))
        #expect(gesture.clickedItem == nil)
        _ = gesture.end()
        #expect(gesture.clickedItem == nil)
    }

    @Test func panLassoAndShiftDoNotOpenCards() {
        let item = note()
        var gesture = PointerGesture()
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        _ = gesture.press(at: start, viewport: Viewport(), notes: [item], selection: [], pan: true)
        #expect(gesture.clickedItem == nil)
        _ = gesture.press(at: start, viewport: Viewport(), notes: [item], selection: [], shift: true)
        #expect(gesture.clickedItem == nil)
        _ = gesture.press(at: .zero, viewport: Viewport(), notes: [item], selection: [])
        #expect(gesture.clickedItem == nil)
        _ = gesture.move(to: start)
        #expect(gesture.clickedItem == nil)
    }

    @Test(arguments: [0.3, 1.0, 4.0])
    func dragThresholdUsesScreenPointsAndInitialFrames(scale: Double) throws {
        let first = note()
        let second = note(500, 230)
        let third = note(-100, 500)
        let notes = [first, second, third]
        let viewport = Viewport(scale: scale, translation: CGPoint(x: 93, y: -57))
        let start = viewport.viewPoint(fromCanvas: CGPoint(x: 170, y: 170))
        var gesture = PointerGesture()
        _ = gesture.press(at: start, viewport: viewport, notes: notes, selection: Set(notes.map(\.id)))
        #expect(gesture.move(to: CGPoint(x: start.x + 3.99, y: start.y)).frames.isEmpty)
        #expect(gesture.state.name == "pressed")
        let atThreshold = gesture.move(to: CGPoint(x: start.x + 4, y: start.y))
        #expect(gesture.state.name == "draggingItems")
        #expect(abs(try #require(atThreshold.frames[first.id]).minX - (100 + 4 / scale)) < 0.000001)
        _ = gesture.move(to: CGPoint(x: start.x + 80, y: start.y - 20))
        let update = gesture.move(to: CGPoint(x: start.x + 24, y: start.y + 12))
        for item in notes {
            let frame = try #require(update.frames[item.id])
            #expect(abs(frame.minX - item.frame.minX - 24 / scale) < 0.000001)
            #expect(abs(frame.minY - item.frame.minY - 12 / scale) < 0.000001)
        }
        let result = gesture.end()
        let completed = try #require(result)
        #expect(completed.frames == Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.frame) }))
        #expect(gesture.state.name == "idle")
    }

    @Test func freshAndUnselectedNotesMoveWithoutAnotherGroup() {
        let first = note()
        let second = note(500)
        var gesture = PointerGesture()
        _ = gesture.press(at: CGPoint(x: 170, y: 170), viewport: Viewport(),
                          notes: [first, second], selection: [second.id])
        let update = gesture.move(to: CGPoint(x: 180, y: 180))
        #expect(Set(update.frames.keys) == [first.id])
        #expect(update.frames[first.id] == first.frame.offsetBy(dx: 10, dy: 10))
    }

    @Test(arguments: [false, true])
    func lassoUsesIntersectionAndInitialSelection(shift: Bool) {
        let first = note()
        let outside = note(500)
        var gesture = PointerGesture()
        let viewport = Viewport(scale: 0.3, translation: CGPoint(x: 90, y: 70))
        _ = gesture.press(at: viewport.viewPoint(fromCanvas: CGPoint(x: 80, y: 80)),
                          viewport: viewport, notes: [first, outside], selection: [outside.id], shift: shift)
        let update = gesture.move(to: viewport.viewPoint(fromCanvas: CGPoint(x: 110, y: 110)))
        #expect(gesture.state.name == "lassoing")
        #expect(update.selection == (shift ? [first.id, outside.id] : [first.id]))
        #expect(update.lasso?.width == 9)
        let retreat = gesture.move(to: viewport.viewPoint(fromCanvas: CGPoint(x: 90, y: 90)))
        #expect(retreat.selection == (shift ? [outside.id] : []))
        #expect(gesture.cancel().selection == [outside.id])
        #expect(gesture.state.name == "idle")
    }

    @Test(arguments: [ResizeHandle.bottomLeft, .bottomRight, .topLeft, .topRight])
    func resizeClampsAtOppositeCorner(handle: ResizeHandle) {
        let rect = CGRect(x: 100, y: 200, width: 240, height: 150)
        let point = handle.point(in: rect)
        let opposite = CGPoint(x: point.x == rect.minX ? rect.maxX : rect.minX,
                               y: point.y == rect.minY ? rect.maxY : rect.minY)
        let frame = handle.resize(rect, by: CGSize(width: (opposite.x - point.x) * 3,
                                                   height: (opposite.y - point.y) * 3))
        #expect(frame.size == CGSize(width: 160, height: 100))
        #expect(frame.minX == opposite.x || frame.maxX == opposite.x)
        #expect(frame.minY == opposite.y || frame.maxY == opposite.y)
    }

    @Test(arguments: [ResizeHandle.left, .right, .bottom, .top])
    func edgeResizeChangesOneAxis(handle: ResizeHandle) {
        let rect = CGRect(x: 100, y: 200, width: 240, height: 150)
        let frame = handle.resize(rect, by: CGSize(width: 500, height: 500))
        switch handle {
        case .left:
            #expect(frame == CGRect(x: 180, y: 200, width: 160, height: 150))
        case .right:
            #expect(frame == CGRect(x: 100, y: 200, width: 740, height: 150))
        case .bottom:
            #expect(frame == CGRect(x: 100, y: 250, width: 240, height: 100))
        case .top:
            #expect(frame == CGRect(x: 100, y: 200, width: 240, height: 650))
        default:
            Issue.record("Expected an edge resize target.")
        }
    }

    @Test func cancelRestoresMoveResizeSelectionAndPan() throws {
        let item = note()
        let initial = Viewport(scale: 4, translation: CGPoint(x: 35, y: -12))
        let start = initial.viewPoint(fromCanvas: CGPoint(x: 170, y: 170))
        for kind in ["move", "resize", "pan"] {
            var gesture = PointerGesture()
            _ = gesture.press(at: start, viewport: initial, notes: [item], selection: [],
                              pan: kind == "pan", handle: kind == "resize" ? (item.id, .topRight) : nil)
            let preview = gesture.move(to: CGPoint(x: start.x + 40, y: start.y + 80))
            if kind == "pan" { #expect(preview.viewport?.translation == CGPoint(x: 75, y: 68)) }
            let restore = gesture.cancel()
            #expect(restore.frames == [item.id: item.frame])
            #expect(restore.selection == [])
            #expect(restore.viewport == initial)
            #expect(gesture.state.name == "idle")
            #expect(gesture.end() == nil)
            #expect(gesture.move(to: .zero).frames.isEmpty)
        }
    }
}

@MainActor
struct BoardGestureTests {
    @Test func completedGesturesSaveAndUndoAsOneActionEach() throws {
        let store = NoteStore(inMemory: true)
        let canvas = BoardSurface(store: store)
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        let manager = try #require(window.undoManager)
        #expect(manager.groupsByEvent)
        canvas.loadNotes()
        let note = try #require(canvas.newNote())
        let start = CGPoint(x: note.frame.midX, y: note.frame.midY)
        for delta in [20.0, 40.0] {
            let current = CGPoint(x: start.x + delta - 20, y: start.y)
            canvas.dragger.beginPointerAction(at: current, shift: false, pan: false)
            canvas.dragger.didMove(to: CGPoint(x: start.x + delta, y: start.y))
            canvas.dragger.didEnd()
        }
        #expect(manager.groupingLevel == 0)
        #expect(try store.load().get().first?.frame == note.frame.offsetBy(dx: 40, dy: 0))
        manager.undo()
        #expect(canvas.notes.first?.frame == note.frame.offsetBy(dx: 20, dy: 0))
        manager.undo()
        #expect(canvas.notes.first?.frame == note.frame)
        #expect(manager.canUndo)
        #expect(try store.load().get().first?.frame == note.frame)
        manager.undo()
        #expect(canvas.notes.isEmpty)
        #expect(try store.load().get().isEmpty)
        #expect(!manager.canUndo)
        manager.redo()
        #expect(canvas.notes.first?.id == note.id)
        #expect(canvas.notes.first?.frame == note.frame)
        manager.redo()
        manager.redo()
        let moved = try #require(canvas.notes.first).frame
        #expect(canvas.resizeHandles.isEmpty)
        let edge = CGPoint(x: moved.maxX - 1, y: moved.midY)
        canvas.dragger.beginPointerAction(at: edge, shift: false, pan: false)
        canvas.dragger.didMove(to: CGPoint(x: edge.x + 40, y: edge.y))
        canvas.dragger.didEnd()
        let translated = try #require(canvas.notes.first).frame
        #expect(translated.size == moved.size)
        #expect(translated == moved.offsetBy(dx: 40, dy: 0))
        manager.undo()
        #expect(try store.load().get().first?.frame == moved)
        manager.redo()
        #expect(try store.load().get().first?.frame == translated)
        canvas.dragger.beginPointerAction(at: CGPoint(x: translated.midX, y: translated.midY), shift: false, pan: false)
        canvas.dragger.didMove(to: CGPoint(x: translated.midX + 90, y: translated.midY + 80))
        canvas.dragger.cancel()
        #expect(canvas.notes.first?.frame == translated)
        window.contentView = nil
    }

    @Test(arguments: [0.3, 1.0, 4.0])
    func notesHaveNoResizeTargetsAndTextControlsReceiveHit(scale: Double) throws {
        let canvas = BoardSurface(store: NoteStore(inMemory: true))
        canvas.frame = CGRect(x: 0, y: 0, width: 1080, height: 720)
        canvas.layoutSubtreeIfNeeded()
        canvas.loadNotes()
        let note = try #require(canvas.newNote())
        canvas.setViewport(Viewport(scale: scale, translation: CGPoint(x: 91, y: -43)))
        canvas.select([note.id])
        #expect(canvas.resizeHandles.isEmpty)
        let rect = canvas.viewRect(fromCanvas: note.frame)
        for handle in ResizeHandle.allCases {
            #expect(canvas.resizeHandle(at: handle.point(in: rect)) == nil)
        }
        canvas.setViewport(Viewport())
        let view = try #require(canvas.entryTiles.first)
        let field = NSTextField(frame: CGRect(x: 20, y: 20, width: 160, height: 50))
        view.addSubview(field)
        let hit = canvas.hitTest(CGPoint(x: note.frame.minX + 40, y: note.frame.minY + 40))
        #expect(hit === field)
    }
}
