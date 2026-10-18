import AppKit
import QuartzCore

public struct Viewport: Equatable, Sendable {
    public private(set) var scale: CGFloat
    public private(set) var translation: CGPoint

    public init(scale: CGFloat = 1, translation: CGPoint = .zero) {
        self.scale = min(max(scale, 0.3), 4)
        self.translation = translation
    }

    public func canvasPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - translation.x) / scale, y: (point.y - translation.y) / scale)
    }

    public func viewPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + translation.x, y: point.y * scale + translation.y)
    }

    public func canvasRect(fromView rect: CGRect) -> CGRect {
        CGRect(origin: canvasPoint(fromView: rect.origin),
               size: CGSize(width: rect.width / scale, height: rect.height / scale))
    }

    public func viewRect(fromCanvas rect: CGRect) -> CGRect {
        CGRect(origin: viewPoint(fromCanvas: rect.origin),
               size: CGSize(width: rect.width * scale, height: rect.height * scale))
    }

    public mutating func pan(by delta: CGSize) {
        translation.x += delta.width
        translation.y += delta.height
    }

    public mutating func zoom(to newScale: CGFloat, around point: CGPoint) {
        let anchor = canvasPoint(fromView: point)
        scale = min(max(newScale, 0.3), 4)
        translation = CGPoint(x: point.x - anchor.x * scale, y: point.y - anchor.y * scale)
    }

    public mutating func magnify(by magnification: CGFloat, at point: CGPoint) {
        guard magnification != 0 else { return }
        zoom(to: scale * (1 + magnification), around: point)
    }

    var transform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: translation.x, ty: translation.y)
    }
}

@MainActor
public final class BoardSurface: NSView, NSMenuItemValidation {
    static var noteCornerRadius: CGFloat { AppPreferences.shared.cornerStyle == .round ? 16 : 0 }
    public private(set) var entryTiles: [EntryTile] = []
    public enum LoadState {
        case empty, populated, loadError(NoteStoreError)
    }

    public private(set) var notes: [NoteRecord] = []
    public private(set) var spaces: [SpaceRecord] = []
    public private(set) var currentSpaceID = SpaceRecord.firstID
    public private(set) var selection: Set<UUID> = []
    public private(set) var loadState: LoadState = .empty
    public private(set) var saveError: String?
    public var onStateChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onNoteCreated: (() -> Void)?
    public let overlayLayer = CAShapeLayer()
    private let overlayView = CanvasOverlayView()
    private let noteStore: NoteStore
    private let boardContentHost = NSView()
    public private(set) var dragger: Driver!
    private var targetViewport = Viewport()
    public var onViewportChange: (() -> Void)?
    public private(set) var viewport: Viewport {
        get {
            guard isCameraAnimating, let transform = boardContentHost.layer?.presentation()?.sublayerTransform else {
                return targetViewport
            }
            return Viewport(scale: transform.m11, translation: CGPoint(x: transform.m41, y: transform.m42))
        }
        set { targetViewport = newValue }
    }
    public var magnification: CGFloat { viewport.scale }
    private var pinchStart: Viewport?
    var isPinching: Bool { pinchStart != nil }
    private var cameraTimer: Timer?
    var isCameraAnimating: Bool { boardContentHost.layer?.animation(forKey: "rayLite.camera") != nil }
    var hasCameraTimer: Bool { cameraTimer != nil }
    var cameraTarget: Viewport { targetViewport }
    private var viewportSize: CGSize?
    private var spaceHeld = false
    private var mouseUpMonitor: Any?
    private var outsideMouseUpMonitor: Any?
    private var editor: NoteEditor?
    var hasNotePage: Bool { editor != nil }
    var onNotePageChange: ((Bool) -> Void)?
    private let focusLayer = CAShapeLayer()
    private var accessibleNotes: [UUID: NoteAccessibilityElement] = [:]
    private var announcedSelection: Set<UUID> = []
    private var announcedValue = ""
    static let handleSize: CGFloat = 10

    public override init(frame: CGRect) {
        noteStore = NoteStore()
        super.init(frame: frame)
        configure()
    }

    public init(store: NoteStore) {
        noteStore = store
        super.init(frame: .zero)
        configure()
    }

    public required init?(coder: NSCoder) {
        noteStore = NoteStore()
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Canvas")
        setAccessibilityHelp("Use Tab or arrow keys to select notes. Press Return to edit the selected note.")
        focusLayer.fillColor = nil
        focusLayer.lineWidth = 3
        overlayLayer.addSublayer(focusLayer)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayPreferencesChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        boardContentHost.wantsLayer = true
        addSubview(boardContentHost)
        overlayLayer.fillColor = nil
        overlayLayer.lineWidth = 2
        overlayView.wantsLayer = true
        overlayView.layer = overlayLayer
        overlayView.autoresizingMask = [.width, .height]
        addSubview(overlayView, positioned: .above, relativeTo: boardContentHost)
        dragger = Driver(canvas: self)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    public func loadNotes() {
        switch noteStore.loadSpaces() {
        case .success(let spaces): self.spaces = spaces
        case .failure(let error):
            loadState = .loadError(error)
            onStateChange?()
            return
        }
        if !spaces.contains(where: { $0.id == currentSpaceID }), let first = spaces.first {
            currentSpaceID = first.id
        }
        switch noteStore.load(spaceID: currentSpaceID) {
        case .success(let loaded):
            entryTiles.forEach { $0.removeFromSuperview() }
            entryTiles = []
            notes = loaded
            selection = []
            saveError = nil
            for index in notes.indices {
                let frame = notes[index].fittedFrame(notes[index].frame)
                if frame != notes[index].frame {
                    var note = notes[index]
                    note.frame = frame
                    switch noteStore.update(note) {
                    case .success: notes[index] = note
                    case .failure(let error): saveError = error.message
                    }
                }
            }
            for note in notes { displayNote(note) }
            loadState = notes.isEmpty ? .empty : .populated
            updateSelectionOverlay()
        case .failure(let error):
            loadState = .loadError(error)
        }
        onStateChange?()
    }

    @discardableResult
    public func switchSpace(_ id: UUID) -> Bool {
        guard spaces.contains(where: { $0.id == id }), finishEditing() else { return false }
        if id == currentSpaceID { return true }
        dragger.cancel()
        interruptCamera()
        currentSpaceID = id
        viewport = Viewport()
        applyViewport()
        loadNotes()
        if case .loadError = loadState { return false }
        return true
    }

    @discardableResult
    public func newSpace() -> SpaceRecord? {
        guard canInsertNotes, finishEditing() else { return nil }
        let number = (spaces.compactMap { space -> Int? in
            guard space.name.hasPrefix("Space") else { return nil }
            return Int(space.name.dropFirst(5))
        }.max() ?? 0) + 1
        let space = SpaceRecord(name: String(format: "Space%02d", number),
                                order: (spaces.map(\.order).max() ?? -1) + 1)
        let previousID = currentSpaceID
        guard restoreSpace(space) else { return nil }
        registerSpaceUndo(space, previousID: previousID, remove: true)
        return space
    }

    private func restoreSpace(_ space: SpaceRecord) -> Bool {
        switch noteStore.insertSpace(space) {
        case .success:
            spaces.append(space)
            return switchSpace(space.id)
        case .failure(let error):
            saveError = error.message
            onStateChange?()
            return false
        }
    }

    private func registerSpaceUndo(_ space: SpaceRecord, previousID: UUID, remove: Bool) {
        guard let manager = undoManager else { return }
        let groups = !manager.isUndoing && !manager.isRedoing
        let groupsByEvent = manager.groupsByEvent
        if groups {
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
        }
        manager.registerUndo(withTarget: self) { canvas in
            guard canvas.finishEditing() else { return }
            if remove {
                switch canvas.noteStore.deleteEmptySpace(id: space.id) {
                case .success(true):
                    if canvas.currentSpaceID == space.id { canvas.currentSpaceID = previousID }
                    canvas.loadNotes()
                case .success(false): return
                case .failure(let error):
                    canvas.saveError = error.message
                    canvas.onStateChange?()
                    return
                }
            } else if !canvas.restoreSpace(space) {
                return
            }
            canvas.registerSpaceUndo(space, previousID: previousID, remove: !remove)
        }
        manager.setActionName("Create Space")
        if groups {
            manager.endUndoGrouping()
            manager.groupsByEvent = groupsByEvent
        }
    }

    @discardableResult
    func renameCurrentSpace(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let previous = spaces.first(where: { $0.id == currentSpaceID }), finishEditing() else { return false }
        switch noteStore.renameSpace(id: currentSpaceID, name: name) {
        case .success:
            loadNotes()
            registerRenameUndo(id: previous.id, name: previous.name)
            return true
        case .failure(let error):
            saveError = error.message
            onStateChange?()
            return false
        }
    }

    private func registerRenameUndo(id: UUID, name: String) {
        registerSpaceAction("Edit Space") { canvas in
            guard canvas.switchSpace(id) else { return }
            _ = canvas.renameCurrentSpace(name)
        }
    }

    @discardableResult
    func deleteCurrentSpace() -> Bool {
        guard finishEditing(), let space = spaces.first(where: { $0.id == currentSpaceID }) else { return false }
        let replacement = SpaceRecord(name: "Space01", order: 0)
        let inserted = spaces.count == 1 ? [replacement] : []
        let destination = spaces.first(where: { $0.id != space.id })?.id ?? replacement.id
        return replaceSpace(space.id, inserting: inserted, notes: [], destination: destination)
    }

    private func replaceSpace(_ id: UUID, inserting: [SpaceRecord], notes: [NoteRecord], destination: UUID) -> Bool {
        guard finishEditing(), let removed = spaces.first(where: { $0.id == id }) else { return false }
        let removedNotes: [NoteRecord]
        switch noteStore.load(spaceID: id) {
        case .success(let records): removedNotes = records
        case .failure(let error):
            saveError = error.message
            onStateChange?()
            return false
        }
        switch noteStore.replaceSpaces(removing: id, inserting: inserting, notes: notes) {
        case .success:
            currentSpaceID = destination
            dragger.cancel()
            interruptCamera()
            viewport = Viewport()
            applyViewport()
            loadNotes()
            registerSpaceAction("Delete Space") { canvas in
                if let inserted = inserting.first {
                    _ = canvas.replaceSpace(inserted.id, inserting: [removed], notes: removedNotes, destination: id)
                } else {
                    canvas.restoreDeletedSpace(removed, notes: removedNotes)
                }
            }
            return true
        case .failure(let error):
            saveError = error.message
            onStateChange?()
            return false
        }
    }

    private func restoreDeletedSpace(_ space: SpaceRecord, notes: [NoteRecord]) {
        switch noteStore.restoreSpace(space, notes: notes) {
        case .success:
            currentSpaceID = space.id
            loadNotes()
            registerSpaceAction("Delete Space") { canvas in
                guard canvas.switchSpace(space.id) else { return }
                _ = canvas.deleteCurrentSpace()
            }
        case .failure(let error):
            saveError = error.message
            onStateChange?()
        }
    }

    private func registerSpaceAction(_ name: String, action: @escaping (BoardSurface) -> Void) {
        guard let manager = undoManager else { return }
        let groups = !manager.isUndoing && !manager.isRedoing
        let groupsByEvent = manager.groupsByEvent
        if groups {
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
        }
        manager.registerUndo(withTarget: self, handler: action)
        manager.setActionName(name)
        if groups {
            manager.endUndoGrouping()
            manager.groupsByEvent = groupsByEvent
        }
    }

    func applyPreferences() {
        for item in entryTiles {
            item.applyColor()
            item.needsLayout = true
        }
        layoutEditor()
        updateSelectionOverlay()
    }

    public func setSelected(_ id: UUID, selected: Bool) {
        guard notes.contains(where: { $0.id == id }) else { return }
        if selected { selection.insert(id) } else { selection.remove(id) }
        updateSelectionOverlay()
    }

    func select(_ ids: Set<UUID>) {
        selection = ids.intersection(Set(notes.map(\.id)))
        updateSelectionOverlay()
    }

    func resizeEntry(id: UUID, frame: CGRect) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let frame = notes[index].fittedFrame(frame)
        notes[index].frame = frame
        if let view = entryTiles.first(where: { $0.id == id }), view.frame != frame { view.frame = frame }
        updateSelectionOverlay()
    }

    func previewFrames(_ frames: [UUID: CGRect]) {
        guard !frames.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var fittedFrames: [UUID: CGRect] = [:]
        for index in notes.indices {
            if let frame = frames[notes[index].id] {
                let fitted = notes[index].fittedFrame(frame)
                notes[index].frame = fitted
                fittedFrames[notes[index].id] = fitted
            }
        }
        for view in entryTiles {
            if let frame = fittedFrames[view.id], view.frame != frame { view.frame = frame }
        }
        updateSelectionOverlay()
        CATransaction.commit()
    }

    public func canvasPoint(from point: CGPoint) -> CGPoint {
        viewport.canvasPoint(fromView: point)
    }

    public func viewPoint(from point: CGPoint) -> CGPoint {
        viewport.viewPoint(fromCanvas: point)
    }

    public func canvasRect(fromView rect: CGRect) -> CGRect { viewport.canvasRect(fromView: rect) }

    public func viewRect(fromCanvas rect: CGRect) -> CGRect { viewport.viewRect(fromCanvas: rect) }

    public func noteID(atView point: CGPoint) -> UUID? {
        let point = canvasPoint(from: point)
        return notes.reversed().first { $0.frame.contains(point) }?.id
    }

    @discardableResult
    public func newNote() -> NoteRecord? {
        guard canInsertNotes, finishEditing() else { return nil }
        layoutSubtreeIfNeeded()
        let center = canvasPoint(from: CGPoint(x: bounds.midX - 1, y: bounds.midY + 10))
        let note = NoteRecord(id: UUID(), text: "",
                              frame: CGRect(x: center.x - 70, y: center.y - 100, width: 140, height: 200),
                              order: (notes.map(\.order).max() ?? -1) + 1, spaceID: currentSpaceID)
        guard insertNote(note) else { return nil }
        onNoteCreated?()
        select([])
        window?.makeFirstResponder(self)
        entryTiles.first { $0.id == note.id }?.fadeIn()
        return note
    }

    public func addSampleNotes() {
        guard canInsertNotes, finishEditing() else { return }
        layoutSubtreeIfNeeded()
        let center = canvasPoint(from: CGPoint(x: bounds.midX, y: bounds.midY))
        for var note in UnboxingSequence.sampleNotes(center: center, order: (notes.map(\.order).max() ?? -1) + 1) {
            note.spaceID = currentSpaceID
            if !insertNote(note) { return }
        }
    }

    var canInsertNotes: Bool {
        if case .loadError = loadState { return false }
        return true
    }

    enum NoteChange {
        case insert(NoteRecord)
        case update(NoteRecord)
        case delete(UUID)
    }

    @discardableResult
    func applyChanges(_ changes: [NoteChange], actionName: String) -> Bool {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard !changes.isEmpty else { return true }
        var inverse: [NoteChange] = []
        var failure: NoteStoreError?
        for change in changes {
            let result: Result<Void, NoteStoreError>
            let previous: NoteRecord?
            switch change {
            case .insert(let note):
                previous = nil
                result = noteStore.insert(note)
            case .update(let note):
                previous = notes.first { $0.id == note.id }
                result = noteStore.update(note)
            case .delete(let id):
                previous = notes.first { $0.id == id }
                result = noteStore.delete(id: id)
            }
            if case .failure(let error) = result {
                failure = error
                break
            }
            switch change {
            case .insert(let note):
                notes.append(note)
                displayNote(note)
                inverse.insert(.delete(note.id), at: 0)
            case .update(let note):
                if let previous, let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[index] = note
                    let view = entryTiles.first { $0.id == note.id }
                    view?.frame = note.frame
                    view?.applyColor()
                    inverse.insert(.update(previous), at: 0)
                }
            case .delete(let id):
                notes.removeAll { $0.id == id }
                if (window?.firstResponder as? EntryTile)?.id == id { window?.makeFirstResponder(self) }
                entryTiles.first { $0.id == id }?.removeFromSuperview()
                entryTiles.removeAll { $0.id == id }
                if let previous { inverse.insert(.insert(previous), at: 0) }
            }
        }
        notes.sort { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        entryTiles.sort { left, right in
            let leftIndex = notes.firstIndex { $0.id == left.id } ?? 0
            let rightIndex = notes.firstIndex { $0.id == right.id } ?? 0
            return leftIndex < rightIndex
        }
        for view in entryTiles { boardContentHost.addSubview(view, positioned: .above, relativeTo: nil) }
        selection.formIntersection(Set(notes.map(\.id)))
        loadState = notes.isEmpty ? .empty : .populated
        saveError = failure?.message
        updateSelectionOverlay()
        onStateChange?()
        if !inverse.isEmpty { registerNoteUndo(inverse, actionName: actionName) }
        return failure == nil
    }

    private func insertNote(_ note: NoteRecord) -> Bool {
        var note = note
        note.frame = NoteTextLayer.fittedFrame(note.frame, text: note.text)
        return applyChanges([.insert(note)], actionName: "Create Note")
    }

    @discardableResult
    func updateText(id: UUID, text: String, content: NoteContent? = nil) -> Bool {
        guard var note = notes.first(where: { $0.id == id }), note.kind == .note else { return false }
        let frame = NoteTextLayer.fittedFrame(note.frame, text: text)
        guard note.text != text || note.frame != frame || content.map({ $0 != note.content }) == true else { return true }
        note.content = content ?? NoteContent(plainText: text)
        note.frame = frame
        return applyChanges([.update(note)], actionName: "Edit Note")
    }

    @objc func newDocument(_ sender: Any?) {
        newNote()
    }

    @objc func delete(_ sender: Any?) {
        guard editor == nil else { return }
        dragger.cancel()
        applyChanges(notes.filter { selection.contains($0.id) }.map { .delete($0.id) }, actionName: "Delete Notes")
    }

    override public func deleteBackward(_ sender: Any?) { delete(sender) }

    override public func deleteForward(_ sender: Any?) { delete(sender) }

    override public func selectAll(_ sender: Any?) {
        guard editor == nil else { return }
        select(Set(notes.map(\.id)))
    }

    @objc func undo(_ sender: Any?) {
        guard editor == nil else { return }
        dragger.cancel()
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        guard editor == nil else { return }
        dragger.cancel()
        undoManager?.redo()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newDocument(_:)) { return canInsertNotes }
        guard editor == nil else { return false }
        if menuItem.action == #selector(undo(_:)) { return undoManager?.canUndo ?? false }
        if menuItem.action == #selector(redo(_:)) { return undoManager?.canRedo ?? false }
        if menuItem.action == #selector(paste(_:)) { return canInsertNotes && ImageImport.canRead(ImageImport.clipboard) }
        if menuItem.action == #selector(delete(_:)) { return !selection.isEmpty }
        if menuItem.action == #selector(selectAll(_:)) { return !notes.isEmpty }
        return true
    }

    @objc func dismissSaveError(_ sender: Any?) {
        saveError = nil
        onStateChange?()
    }

    override public func insertNewline(_ sender: Any?) {
        guard selection.count == 1, let id = selection.first else { return }
        beginEditing(id)
    }

    func beginEditing(_ id: UUID) {
        if let editor, editor.noteID == id {
            guard editor.destination == .board else { return }
            setNotePageVisible(true, editor: editor)
            window?.makeFirstResponder(editor.textView)
            return
        }
        guard finishEditing(), let window,
              let note = notes.first(where: { $0.id == id }), note.kind == .note else { return }
        dragger.cancel()
        interruptCamera()
        spaceHeld = false
        select([id])
        let editor = NoteEditor(note: note)
        editor.onExit = { [weak self] in self?.finishEditing(animated: true) ?? true }
        editor.onOutsideClick = { [weak self] in
            guard let self, self.finishEditing(animated: true) else { return }
            self.select([])
        }
        editor.onReturn = { [weak self, weak editor] in
            guard let self, let editor, self.editor === editor else { return }
            self.removeNoteEditor(editor)
        }
        self.editor = editor
        addSubview(editor)
        layoutEditor()
        setNotePageVisible(true, editor: editor, initial: true)
        window.makeFirstResponder(editor.textView)
    }

    @discardableResult
    func finishEditing(animated: Bool = false) -> Bool {
        guard let editor else { return true }
        guard updateText(id: editor.noteID, text: editor.content.plainText, content: editor.content) else { return false }
        window?.makeFirstResponder(self)
        if animated {
            setNotePageVisible(false, editor: editor)
        } else {
            removeNoteEditor(editor)
        }
        return true
    }

    private func setNotePageVisible(_ visible: Bool, editor: NoteEditor, initial: Bool = false) {
        let rect = notes.first { $0.id == editor.noteID }.map { viewRect(fromCanvas: $0.frame) } ?? .zero
        let card = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        entryTiles.first { $0.id == editor.noteID }?.isHidden = true
        let destination: NotePageTransition.Destination = visible ? .page : .board
        overlayLayer.removeAnimation(forKey: "rayLite.noteBoard")
        overlayLayer.opacity = 0
        if let layer = boardContentHost.layer {
            let animation = NotePageTransition.animation(keyPath: "opacity", to: visible ? 0 : 1, destination: destination)
            SpringCore.shared.add(animation, to: layer, key: "rayLite.noteBoard")
            let expanded = CATransform3DScale(CATransform3DMakeTranslation(-bounds.width * 0.04, -bounds.height * 0.04, 0), 1.08, 1.08, 1)
            let movement = NotePageTransition.animation(keyPath: "transform",
                to: NSValue(caTransform3D: visible ? expanded : CATransform3DIdentity), destination: destination)
            SpringCore.shared.add(movement, to: layer, key: "rayLite.noteBoardPosition")
        }
        if let back = editor.backControl.layer {
            let hidden = CATransform3DMakeTranslation(-64, 0, 0)
            if initial { back.transform = hidden }
            let animation = NotePageTransition.animation(keyPath: "transform",
                to: NSValue(caTransform3D: visible ? CATransform3DIdentity : hidden), destination: destination)
            SpringCore.shared.add(animation, to: back, key: "rayLite.noteBackPosition")
        }
        onNotePageChange?(visible)
        editor.present(destination, from: card, scale: magnification, initial: initial)
    }

    private func removeNoteEditor(_ editor: NoteEditor) {
        editor.stopTransition()
        self.editor = nil
        editor.removeFromSuperview()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [boardContentHost.layer, overlayLayer].compactMap({ $0 }) {
            layer.removeAnimation(forKey: "rayLite.noteBoard")
            layer.opacity = 1
        }
        boardContentHost.layer?.removeAnimation(forKey: "rayLite.noteBoardPosition")
        boardContentHost.layer?.transform = CATransform3DIdentity
        let selection = CABasicAnimation(keyPath: "opacity")
        selection.fromValue = Float(0)
        selection.toValue = Float(1)
        selection.duration = 0.4
        selection.timingFunction = CAMediaTimingFunction(controlPoints: 0.9, 0, 1, 1)
        overlayLayer.add(selection, forKey: "rayLite.noteBoard")
        entryTiles.first { $0.id == editor.noteID }?.isHidden = false
        CATransaction.commit()
        onNotePageChange?(false)
    }

    private func layoutEditor() {
        guard let editor else { return }
        editor.frame = bounds
        editor.needsLayout = true
    }

    private func displayNote(_ note: NoteRecord) {
        let view = EntryTile(note: note)
        view.canvas = self
        boardContentHost.addSubview(view)
        entryTiles.append(view)
        needsLayout = true
    }

    func configureNoteCard(_ view: EntryTile) {
        guard notes.first(where: { $0.id == view.id })?.kind == .note else { return }
        view.container.cornerRadius = Self.noteCornerRadius
        view.container.backgroundColor = NotePageTransition.cardColor.cgColor
        view.elevationOutline.shadowPath = CGPath(roundedRect: view.bounds,
            cornerWidth: Self.noteCornerRadius, cornerHeight: Self.noteCornerRadius, transform: nil)
    }

    func updateSelectionOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlayView.frame = bounds
        overlayLayer.contentsScale = window?.backingScaleFactor ?? 1
        overlayLayer.strokeColor = NSColor.white.cgColor
        let path = CGMutablePath()
        for note in notes where selection.contains(note.id) {
            let outset: CGFloat = note.kind == .note ? 1 : 4
            let rect = viewRect(fromCanvas: note.frame).insetBy(dx: -outset, dy: -outset)
            let radius = (note.kind == .image ? 0 : Self.noteCornerRadius) * magnification + outset
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        overlayLayer.path = path
        let focusedNote = window?.firstResponder as? EntryTile
        let focusRect: CGRect?
        if let focusedNote, focusedNote.canvas === self {
            focusRect = viewRect(fromCanvas: focusedNote.frame).insetBy(dx: -4, dy: -4)
        } else {
            focusRect = nil
        }
        focusLayer.path = focusRect.map { CGPath(roundedRect: $0, cornerWidth: 8, cornerHeight: 8, transform: nil) }
        focusLayer.strokeColor = NSColor.keyboardFocusIndicatorColor.cgColor
        focusLayer.contentsScale = overlayLayer.contentsScale
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        overlayLayer.lineWidth = contrast ? 3 : 2
        CATransaction.commit()
        window?.invalidateCursorRects(for: self)
        let value = accessibilityValue() as? String ?? ""
        if announcedSelection != selection || announcedValue != value {
            let selectionChanged = announcedSelection != selection
            announcedSelection = selection
            announcedValue = value
            if selectionChanged { onSelectionChange?() }
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    var resizeHandles: [(ResizeHandle, CGRect)] {
        guard selection.count == 1, let note = notes.first(where: { selection.contains($0.id) }),
              note.kind != .note else { return [] }
        let rect = viewRect(fromCanvas: note.frame)
        return ResizeHandle.allCases.map { ($0, $0.target(in: rect, thickness: Self.handleSize)) }
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        guard !spaceHeld else { return }
        for (handle, rect) in resizeHandles {
            let visible = rect.intersection(visibleRect)
            if !visible.isEmpty { addCursorRect(visible, cursor: handle.cursor) }
        }
    }

    func resizeHandle(at point: CGPoint) -> (UUID, ResizeHandle)? {
        guard let id = selection.first else { return nil }
        guard let handle = resizeHandles.first(where: { $0.1.contains(point) }) else { return nil }
        return (id, handle.0)
    }

    func setViewport(_ viewport: Viewport) {
        interruptCamera()
        self.viewport = viewport
        applyViewport()
    }

    func panBy(_ delta: CGSize) {
        interruptCamera()
        viewport.pan(by: delta)
        applyViewport()
    }

    override public func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let previous = viewportSize, previous != bounds.size {
            interruptCamera()
            viewport.pan(by: CGSize(width: (bounds.width - previous.width) / 2,
                                    height: (bounds.height - previous.height) / 2))
        }
        viewportSize = bounds.size
        boardContentHost.frame = bounds
        applyViewport()
    }

    private func applyViewport() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        boardContentHost.layer?.anchorPoint = .zero
        boardContentHost.layer?.position = .zero
        boardContentHost.layer?.sublayerTransform = CATransform3DMakeAffineTransform(targetViewport.transform)
        entryTiles.forEach { $0.refreshImageThumbnail() }
        updateSelectionOverlay()
        layoutEditor()
        CATransaction.commit()
        onViewportChange?()
    }

    func interruptCamera() {
        if isCameraAnimating, let layer = boardContentHost.layer {
            SpringCore.shared.cancel(layer, keyPath: "sublayerTransform", behavior: .keepCurrentValue)
            let transform = layer.sublayerTransform
            viewport = Viewport(scale: transform.m11, translation: CGPoint(x: transform.m41, y: transform.m42))
        }
        cameraTimer?.invalidate()
        cameraTimer = nil
        entryTiles.forEach { $0.interruptFade() }
    }

    private func moveCamera(to target: Viewport) {
        interruptCamera()
        pinchStart = nil
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              target != viewport, let layer = boardContentHost.layer else {
            viewport = target
            applyViewport()
            return
        }
        let animation = SpringCore.shared.animateResponse(keyPath: "sublayerTransform",
            from: NSValue(caTransform3D: layer.sublayerTransform),
            to: NSValue(caTransform3D: CATransform3DMakeAffineTransform(target.transform)),
            preset: SpringCatalog.groupMotion)
        viewport = target
        SpringCore.shared.add(animation, to: layer, key: "rayLite.camera")
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.window != nil else {
                    timer.invalidate()
                    return
                }
                self.updateSelectionOverlay()
                self.layoutEditor()
                self.onViewportChange?()
                if !self.isCameraAnimating {
                    timer.invalidate()
                    self.cameraTimer = nil
                }
            }
        }
        cameraTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func zoomCamera(to scale: CGFloat) {
        var target = viewport
        target.zoom(to: scale, around: CGPoint(x: bounds.midX, y: bounds.midY))
        moveCamera(to: target)
    }

    @objc func zoomIn(_ sender: Any?) { zoomCamera(to: viewport.scale * 1.25) }

    @objc func zoomOut(_ sender: Any?) { zoomCamera(to: viewport.scale / 1.25) }

    @objc func actualSize(_ sender: Any?) { zoomCamera(to: 1) }

    @objc func fitContent(_ sender: Any?) {
        guard let first = notes.first else { return }
        let content = notes.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let available = bounds.insetBy(dx: 64, dy: 80)
        let scale = min(max(min(available.width / content.width, available.height / content.height), 0.3), 4)
        moveCamera(to: Viewport(scale: scale,
            translation: CGPoint(x: available.midX - content.midX * scale,
                                 y: available.midY - content.midY * scale)))
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if window == nil {
            entryTiles.forEach { $0.stopAnimations() }
        }
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                name: NSWindow.didResignKeyNotification, object: window)
        }
        windowResignedKey()
    }

    @objc private func windowResignedKey() {
        interruptCamera()
        dragger.cancel()
        spaceHeld = false
        if let pinchStart { viewport = pinchStart }
        pinchStart = nil
        applyViewport()
    }

    public func commitItemFrames() {
        switch noteStore.load() {
        case .success(let saved):
            commitFrames(from: Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0.frame) }), actionName: "Move Notes")
        case .failure(let error):
            saveError = error.message
            onStateChange?()
        }
    }

    func commitFrames(from initial: [UUID: CGRect], actionName: String) {
        let changed = notes.filter { initial[$0.id] != nil && initial[$0.id] != $0.frame }
        guard !changed.isEmpty else { return }
        previewFrames(initial)
        applyChanges(changed.map { .update($0) }, actionName: actionName)
    }

    private func registerNoteUndo(_ changes: [NoteChange], actionName: String) {
        let spaceID = currentSpaceID
        guard let manager = undoManager else { return }
        let groups = !manager.isUndoing && !manager.isRedoing
        let groupsByEvent = manager.groupsByEvent
        if groups {
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
        }
        manager.registerUndo(withTarget: self) { canvas in
            guard canvas.switchSpace(spaceID) else { return }
            let restored = Set(changes.compactMap { change -> UUID? in
                if case .insert(let note) = change { return note.id }
                return nil
            })
            canvas.applyChanges(changes, actionName: actionName)
            if !restored.isEmpty { canvas.select(restored) }
        }
        manager.setActionName(actionName)
        if groups {
            manager.endUndoGrouping()
            manager.groupsByEvent = groupsByEvent
        }
    }

    @objc private func displayPreferencesChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            boardContentHost.layer?.removeAnimation(forKey: "rayLite.camera")
            cameraTimer?.invalidate()
            cameraTimer = nil
            entryTiles.forEach { $0.stopAnimations() }
            applyViewport()
        }
        entryTiles.forEach { $0.applyColor(); $0.needsLayout = true }
        updateSelectionOverlay()
        onStateChange?()
    }

    override public func accessibilityValue() -> Any? {
        let selected = notes.filter { selection.contains($0.id) }
        return selected.isEmpty ? "No selected notes" : selected.map { $0.text.isEmpty ? "Empty note" : $0.text }.joined(separator: ", ")
    }

    override public func accessibilityChildren() -> [Any]? {
        let ids = Set(notes.map(\.id))
        accessibleNotes = accessibleNotes.filter { ids.contains($0.key) }
        var children: [Any] = notes.map { note in
            if let element = accessibleNotes[note.id] { return element }
            let element = NoteAccessibilityElement(id: note.id, canvas: self)
            accessibleNotes[note.id] = element
            return element
        }
        if let editor { children.append(editor) }
        return children
    }

    override public func accessibilitySelectedChildren() -> [Any]? {
        accessibilityChildren()?.filter { ($0 as? NoteAccessibilityElement).map { selection.contains($0.id) } ?? false }
    }

    override public func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        updateSelectionOverlay()
        return accepted
    }

    override public func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.updateSelectionOverlay() }
        return accepted
    }

    func navigateNotes(backward: Bool, tab: Bool) {
        let current = (window?.firstResponder as? EntryTile)?.id
        let index = current.flatMap { id in notes.firstIndex { $0.id == id } }
        let next = index.map { $0 + (backward ? -1 : 1) } ?? (backward ? notes.count - 1 : 0)
        guard notes.indices.contains(next) else {
            if tab {
                if backward { window?.makeFirstResponder(self) }
                else { window?.makeFirstResponder(nextValidKeyView) }
            } else if !notes.isEmpty {
                focusNote(notes[backward ? notes.count - 1 : 0].id)
            }
            return
        }
        focusNote(notes[next].id)
    }

    func focusNote(_ id: UUID) {
        guard let view = entryTiles.first(where: { $0.id == id }) else { return }
        select([id])
        window?.makeFirstResponder(view)
        let rect = viewRect(fromCanvas: view.frame)
        if !bounds.insetBy(dx: 16, dy: 64).contains(rect) {
            panBy(CGSize(width: bounds.midX - rect.midX, height: bounds.midY - rect.midY))
        }
        updateSelectionOverlay()
        if let element = accessibilityChildren()?.compactMap({ $0 as? NoteAccessibilityElement }).first(where: { $0.id == id }) {
            NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
        }
    }

    override public var acceptsFirstResponder: Bool { true }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let editor, editor.isTransitioning { return self }
        if let editor, editor.destination == .page {
            return editor.hitTest(local)
        }
        if !spaceHeld, resizeHandle(at: local) == nil {
            let canvasPoint = canvasPoint(from: local)
            if let top = entryTiles.reversed().first(where: { $0.frame.contains(canvasPoint) }),
               let hit = top.hitTest(canvasPoint), hit is NSControl || hit is NSTextView {
                return hit
            }
        }
        return self
    }

    override public func mouseDown(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let editor, editor.isTransitioning {
            guard event.clickCount < 2 else { return }
            let visible = editor.destination == .board
            if visible {
                setNotePageVisible(true, editor: editor)
                window?.makeFirstResponder(editor.textView)
            } else {
                finishEditing(animated: true)
            }
            return
        }
        interruptCamera()
        window?.makeFirstResponder(self)
        guard finishEditing() else { return }
        dragger.beginPointerAction(at: convert(event.locationInWindow, from: nil),
                         shift: event.modifierFlags.contains(.shift), pan: spaceHeld)
        startPointerTracking()
    }

    override public func mouseDragged(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        dragger.didMove(to: convert(event.locationInWindow, from: nil))
    }

    override public func mouseUp(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        dragger.didEnd()
    }

    private func startPointerTracking() {
        stopPointerTracking()
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.dragger.didEnd()
            return event
        }
        outsideMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragger.didEnd() }
        }
    }

    func stopPointerTracking() {
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        if let outsideMouseUpMonitor { NSEvent.removeMonitor(outsideMouseUpMonitor) }
        mouseUpMonitor = nil
        outsideMouseUpMonitor = nil
    }

    override public func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 48 {
                if event.modifierFlags.contains(.shift), window?.firstResponder === self {
                    window?.selectPreviousKeyView(self)
                } else {
                    navigateNotes(backward: event.modifierFlags.contains(.shift), tab: true)
                }
                return
            }
            if [123, 124, 125, 126].contains(event.keyCode) {
                navigateNotes(backward: [123, 126].contains(event.keyCode), tab: false)
                return
            }
        }
        if event.keyCode == 53 {
            dragger.cancel()
            return
        }
        if event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            spaceHeld = true
            window?.invalidateCursorRects(for: self)
            return
        }
        interpretKeyEvents([event])
    }

    override public func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
        } else {
            super.keyUp(with: event)
        }
    }

    override public func magnify(with event: NSEvent) {
        handleMagnify(at: convert(event.locationInWindow, from: nil),
                      magnification: event.magnification, phase: event.phase)
    }

    func handleMagnify(at point: CGPoint, magnification: CGFloat, phase: NSEvent.Phase) {
        interruptCamera()
        if phase.contains(.cancelled) {
            if let pinchStart { viewport = pinchStart }
            pinchStart = nil
        } else {
            if pinchStart == nil || phase.contains(.began) { pinchStart = viewport }
            viewport.magnify(by: magnification, at: point)
            if phase.contains(.ended) || phase.isEmpty { pinchStart = nil }
        }
        applyViewport()
    }

    override public func scrollWheel(with event: NSEvent) {
        panBy(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
    }
}

@MainActor
private final class CanvasOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
