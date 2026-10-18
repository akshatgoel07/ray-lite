import AppKit
import QuartzCore

enum ResizeHandle: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight
    case left, right, bottom, top

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : isRight ? rect.maxX : rect.midX,
                y: isBottom ? rect.minY : isTop ? rect.maxY : rect.midY)
    }

    private var isLeft: Bool { self == .bottomLeft || self == .topLeft || self == .left }
    private var isRight: Bool { self == .bottomRight || self == .topRight || self == .right }
    private var isBottom: Bool { self == .bottomLeft || self == .bottomRight || self == .bottom }
    private var isTop: Bool { self == .topLeft || self == .topRight || self == .top }

    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition
        switch self {
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .left: position = .left
        case .right: position = .right
        case .bottom: position = .bottom
        case .top: position = .top
        }
        return .frameResize(position: position, directions: .all)
    }

    func target(in rect: CGRect, thickness: CGFloat) -> CGRect {
        let point = point(in: rect)
        let width = self == .top || self == .bottom ? max(0, rect.width - thickness) : thickness
        let height = self == .left || self == .right ? max(0, rect.height - thickness) : thickness
        return CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    func resize(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let x = isLeft ? min(rect.minX + delta.width, rect.maxX - 160) : rect.minX
        let y = isBottom ? min(rect.minY + delta.height, rect.maxY - 100) : rect.minY
        let right = isRight ? max(rect.maxX + delta.width, rect.minX + 160) : rect.maxX
        let top = isTop ? max(rect.maxY + delta.height, rect.minY + 100) : rect.maxY
        return CGRect(x: x, y: y, width: right - x, height: top - y)
    }
}

struct PointerGesture {
    struct Press {
        let point: CGPoint
        let viewport: Viewport
        let initialSelection: Set<UUID>
        let frames: [UUID: CGRect]
        let hit: UUID?
        let shift: Bool
        let selection: Set<UUID>
        let imageIDs: Set<UUID>
    }

    enum State {
        case idle
        case pressed(Press)
        case draggingItems(Press)
        case lassoing(Press)
        case resizing(Press, UUID, ResizeHandle)
        case panning(Press)

        var press: Press? {
            switch self {
            case .idle: return nil
            case .pressed(let press), .draggingItems(let press), .lassoing(let press),
                 .resizing(let press, _, _), .panning(let press): return press
            }
        }

        var name: String {
            switch self {
            case .idle: return "idle"
            case .pressed: return "pressed"
            case .draggingItems: return "draggingItems"
            case .lassoing: return "lassoing"
            case .resizing: return "resizing"
            case .panning: return "panning"
            }
        }
    }

    struct Update {
        var selection: Set<UUID>?
        var frames: [UUID: CGRect] = [:]
        var viewport: Viewport?
        var lasso: CGRect?
    }

    private(set) var state: State = .idle

    var clickedItem: UUID? {
        guard case .pressed(let press) = state, !press.shift else { return nil }
        return press.hit
    }

    mutating func press(at point: CGPoint, viewport: Viewport, notes: [NoteRecord],
                        selection: Set<UUID>, shift: Bool = false, pan: Bool = false,
                        handle: (UUID, ResizeHandle)? = nil) -> Update {
        let hit = notes.reversed().first { $0.frame.contains(viewport.canvasPoint(fromView: point)) }?.id
        var selected = selection
        if !pan, handle == nil {
            if let hit {
                if shift {
                    if !selected.insert(hit).inserted { selected.remove(hit) }
                } else if !selected.contains(hit) {
                    selected = [hit]
                }
            } else if !shift {
                selected = []
            }
        }
        let press = Press(point: point, viewport: viewport, initialSelection: selection,
                          frames: Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.frame) }),
                          hit: hit, shift: shift, selection: selected, imageIDs: Set(notes.filter { $0.kind == .image }.map(\.id)))
        if pan {
            state = .panning(press)
        } else if let (id, corner) = handle {
            state = .resizing(press, id, corner)
        } else {
            state = .pressed(press)
        }
        return Update(selection: selected)
    }

    mutating func move(to point: CGPoint) -> Update {
        guard let press = state.press else { return Update() }
        let dx = point.x - press.point.x
        let dy = point.y - press.point.y
        let delta = CGSize(width: dx / press.viewport.scale, height: dy / press.viewport.scale)
        if case .pressed = state {
            guard hypot(dx, dy) >= 4 else { return Update() }
            state = press.hit == nil ? .lassoing(press) : .draggingItems(press)
        }
        switch state {
        case .draggingItems:
            let frames = press.frames.filter { press.selection.contains($0.key) }
                .mapValues { $0.offsetBy(dx: delta.width, dy: delta.height) }
            return Update(frames: frames)
        case .lassoing:
            let start = press.viewport.canvasPoint(fromView: press.point)
            let end = press.viewport.canvasPoint(fromView: point)
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            let hits = Set(press.frames.filter { rect.intersects($0.value) }.keys)
            return Update(selection: press.shift ? press.initialSelection.union(hits) : hits,
                          lasso: press.viewport.viewRect(fromCanvas: rect))
        case .resizing(_, let id, let handle):
            guard let frame = press.frames[id] else { return Update() }
            return Update(frames: [id: press.imageIDs.contains(id) ? handle.resizeImage(frame, by: delta) : handle.resize(frame, by: delta)])
        case .panning:
            var viewport = press.viewport
            viewport.pan(by: CGSize(width: dx, height: dy))
            return Update(viewport: viewport)
        case .idle, .pressed:
            return Update()
        }
    }

    mutating func cancel() -> Update {
        guard let press = state.press else { return Update() }
        state = .idle
        return Update(selection: press.initialSelection, frames: press.frames, viewport: press.viewport)
    }

    mutating func end() -> (frames: [UUID: CGRect], name: String)? {
        defer { state = .idle }
        switch state {
        case .draggingItems(let press): return (press.frames, "Move Notes")
        case .resizing(let press, _, _): return (press.frames, "Resize Note")
        default: return nil
        }
    }
}

@MainActor
public final class Driver {
    private(set) var gesture = PointerGesture()
    private let lassoView = NSView()
    public weak var canvas: BoardSurface?

    public init(canvas: BoardSurface) {
        self.canvas = canvas
        lassoView.wantsLayer = true
        lassoView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        lassoView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        lassoView.layer?.borderWidth = 1
    }

    func beginPointerAction(at point: CGPoint, shift: Bool, pan: Bool) {
        guard let canvas else { return }
        if gesture.state.press != nil { cancel() }
        apply(gesture.press(at: point, viewport: canvas.viewport, notes: canvas.notes,
                            selection: canvas.selection, shift: shift, pan: pan,
                            handle: canvas.resizeHandle(at: point)))
    }

    func didMove(to point: CGPoint) {
        apply(gesture.move(to: point))
    }

    func didEnd() {
        let clickedItem = gesture.clickedItem
        let completed = gesture.end()
        lassoView.removeFromSuperview()
        canvas?.stopPointerTracking()
        if let completed { canvas?.commitFrames(from: completed.frames, actionName: completed.name) }
        if let clickedItem { canvas?.beginEditing(clickedItem) }
    }

    func cancel() {
        apply(gesture.cancel())
        lassoView.removeFromSuperview()
        canvas?.stopPointerTracking()
    }

    private func apply(_ update: PointerGesture.Update) {
        guard let canvas else { return }
        if let selection = update.selection { canvas.select(selection) }
        canvas.previewFrames(update.frames)
        if let viewport = update.viewport { canvas.setViewport(viewport) }
        if let rect = update.lasso {
            lassoView.frame = rect
            if lassoView.superview == nil { canvas.addSubview(lassoView) }
        }
    }
}
