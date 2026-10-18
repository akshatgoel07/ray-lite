import AppKit

@MainActor
final class NoteTextView: NSTextView {
    private struct Snapshot {
        let content: NoteContent
        let selection: NSRange
        let marks: Set<NoteMark>
    }

    private let textUndoManager = UndoManager()
    private(set) var content = NoteContent(plainText: "")
    private var marks: Set<NoteMark> = []
    private var typingEnd: Int?
    private var appliesEdit = false
    var onExit: (() -> Bool)?
    var onContentChange: (() -> Void)?
    override var undoManager: UndoManager? { textUndoManager }

    override var string: String {
        get { super.string }
        set { load(NoteContent(plainText: newValue)) }
    }

    func load(_ content: NoteContent) {
        self.content = content
        marks = []
        typingEnd = nil
        render(selection: NSRange(location: 0, length: 0))
        textUndoManager.removeAllActions()
        textUndoManager.groupsByEvent = false
    }

    private func render(selection: NSRange) {
        appliesEdit = true
        textStorage?.setAttributedString(NoteBlockRendering.text(content))
        setSelectedRange(NSRange(location: min(selection.location, (super.string as NSString).length),
                                 length: min(selection.length, max(0, (super.string as NSString).length - selection.location))))
        let index = content.position(at: selectedRange().location).block
        typingAttributes = NoteBlockRendering.attributes(style: content.blocks[index].style, marks: marks)
        appliesEdit = false
        needsDisplay = true
        onContentChange?()
    }

    func selectionChanged() {
        guard !appliesEdit else { return }
        if selectedRange().length > 0 || selectedRange().location != typingEnd { typingEnd = nil }
        let runs = content.selectedRuns(in: NSRange(location: max(0, selectedRange().location - 1), length: 1))
        marks = runs.last?.marks ?? []
        typingAttributes = NoteBlockRendering.attributes(style: content.blocks[content.position(at: selectedRange().location).block].style, marks: marks)
    }

    private var snapshot: Snapshot { Snapshot(content: content, selection: selectedRange(), marks: marks) }

    private func register(_ snapshot: Snapshot) {
        textUndoManager.beginUndoGrouping()
        textUndoManager.registerUndo(withTarget: self) { target in target.restore(snapshot) }
        textUndoManager.endUndoGrouping()
    }

    private func restore(_ snapshot: Snapshot) {
        register(self.snapshot)
        content = snapshot.content
        marks = snapshot.marks
        typingEnd = nil
        render(selection: snapshot.selection)
        didChangeText()
    }

    private func edit(typing: Bool = false, undoSelection: NSRange? = nil, _ change: (inout NoteContent) -> NSRange) {
        let selection = selectedRange()
        if !typing || typingEnd != selection.location || selection.length > 0 {
            register(Snapshot(content: content, selection: undoSelection ?? selection, marks: marks))
        }
        let next = change(&content)
        typingEnd = typing ? next.location : nil
        render(selection: next)
        didChangeText()
        scrollRangeToVisible(next)
    }

    @objc func undo(_ sender: Any?) { typingEnd = nil; textUndoManager.undo() }
    @objc func redo(_ sender: Any?) { typingEnd = nil; textUndoManager.redo() }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return textUndoManager.canUndo }
        if menuItem.action == #selector(redo(_:)) { return textUndoManager.canRedo }
        return super.validateMenuItem(menuItem)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        let selection = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let activeMarks = marks
        edit(typing: !text.contains("\n")) { content in
            var caret = content.replace(selection, with: text, marks: activeMarks)
            let index = content.position(at: caret).block
            if content.consumeTrigger(at: index) { caret = content.range(of: index).location + content.blocks[index].style.prefixLength }
            return NSRange(location: caret, length: 0)
        }
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        marks = []
        edit { content in
            let index = content.position(at: selection.location).block
            let block = content.blocks[index]
            let emptyList = block.style.prefixLength > 0 && block.text.isEmpty
            var range = selection
            if emptyList {
                content.setStyle(.body, at: index)
                range = NSRange(location: content.range(of: index).location, length: 0)
            }
            let continuation = !emptyList && block.style.prefixLength > 0 ? block.style : .body
            return NSRange(location: content.replace(range, with: "\n", continuation: continuation), length: 0)
        }
    }

    override func insertTab(_ sender: Any?) { insertText("\t", replacementRange: NSRange(location: NSNotFound, length: 0)) }

    override func insertBacktab(_ sender: Any?) {
        let index = content.position(at: selectedRange().location).block
        guard content.blocks[index].style.prefixLength > 0 else { return }
        applyBlockStyle(.body, at: index, moveToStart: true)
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        let position = content.position(at: selection.location)
        if selection.length == 0, position.character == 0, content.blocks[position.block].style.prefixLength > 0 {
            applyBlockStyle(.body, at: position.block, moveToStart: true)
            return
        }
        guard selection.length > 0 || selection.location > 0 else { return }
        edit { content in
            let range: NSRange
            if selection.length > 0 { range = selection }
            else { range = (content.editorText as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1) }
            return NSRange(location: content.replace(range, with: ""), length: 0)
        }
    }

    override func deleteForward(_ sender: Any?) {
        var range = selectedRange()
        if range.length == 0 {
            guard range.location < (content.editorText as NSString).length else { return }
            range = (content.editorText as NSString).rangeOfComposedCharacterSequence(at: range.location)
        }
        edit { NSRange(location: $0.replace(range, with: ""), length: 0) }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let text: String?
        if let plain = pasteboard.string(forType: .string) { text = plain }
        else if let data = pasteboard.data(forType: .rtf) { text = NSAttributedString(rtf: data, documentAttributes: nil)?.string }
        else { text = nil }
        guard let text else { return }
        pastePlainText(text)
    }

    func pastePlainText(_ text: String) {
        let selection = selectedRange()
        marks = []
        let url = URL(string: text)
        let link = url?.scheme == "https" || url?.scheme == "http" ? text : nil
        edit { NSRange(location: $0.replace(selection, with: text, link: link), length: 0) }
    }

    override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        deleteBackward(sender)
    }

    func applyFormat(_ mark: NoteMark?, collapse: Bool = false) {
        let selection = selectedRange()
        guard selection.length > 0 else {
            if let mark {
                if marks.contains(mark) { marks.remove(mark) } else { marks.insert(mark) }
            } else { marks = [] }
            typingEnd = nil
            return
        }
        edit(undoSelection: NSRange(location: NSMaxRange(selection), length: 0)) { content in
            content.format(selection, mark: mark)
            marks = content.selectedRuns(in: NSRange(location: NSMaxRange(selection) - 1, length: 1)).last?.marks ?? []
            return collapse ? NSRange(location: NSMaxRange(selection), length: 0) : selection
        }
    }

    func applyBlockStyle(_ style: NoteBlockStyle, at index: Int, moveToStart: Bool = false) {
        let position = content.position(at: selectedRange().location)
        edit { content in
            content.setStyle(style, at: index)
            let location = content.range(of: index).location + style.prefixLength + (moveToStart ? 0 : position.block == index ? position.character : 0)
            return NSRange(location: location, length: 0)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.keyCode == 126 || event.keyCode == 125 {
            let target = event.keyCode == 126 ? 0 : (string as NSString).length
            let selection = selectedRange()
            setSelectedRange(flags.contains(.shift)
                ? NSRange(location: min(selection.location, target), length: abs(selection.location - target))
                : NSRange(location: target, length: 0))
            scrollRangeToVisible(selectedRange())
            return true
        }
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": applyFormat(.bold)
        case "i": applyFormat(.italic)
        case "u": applyFormat(.underline)
        case "x" where flags.contains(.shift): applyFormat(.strikethrough)
        case "k": break
        case "z": flags.contains(.shift) ? redo(nil) : undo(nil)
        case "4": applyBlockStyle(.body, at: content.position(at: selectedRange().location).block)
        case "l": applyBlockStyle(.list, at: content.position(at: selectedRange().location).block)
        case "t": applyBlockStyle(.task, at: content.position(at: selectedRange().location).block)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return }
        if event.keyCode == 48, event.modifierFlags.contains(.shift) { insertBacktab(nil); return }
        if event.modifierFlags.contains(.command), performKeyEquivalent(with: event) { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {}

    func blockRect(at character: Int) -> CGRect {
        guard let manager = layoutManager, let container = textContainer else { return .zero }
        manager.ensureLayout(for: container)
        if character >= (string as NSString).length {
            let rect = manager.extraLineFragmentRect
            if rect.height > 0 { return rect }
        }
        guard manager.numberOfGlyphs > 0 else { return CGRect(x: 8, y: 0, width: 600, height: 69.015625) }
        return manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: min(character, (string as NSString).length - 1)), effectiveRange: nil)
    }

    func insertionRect() -> CGRect {
        guard let manager = layoutManager else { return .zero }
        let selection = selectedRange()
        let style = content.blocks[content.position(at: selection.location).block].style
        let line = blockRect(at: selection.location)
        var x: CGFloat = 8
        let length = (string as NSString).length
        if length > 0, selection.location < length || !string.hasSuffix("\n") {
            let character = min(selection.location, length - 1)
            let count = manager.getLineFragmentInsertionPoints(forCharacterAt: character, alternatePositions: false,
                inDisplayOrder: false, positions: nil, characterIndexes: nil)
            if count > 0 {
                var positions = [CGFloat](repeating: 0, count: count)
                var indexes = [Int](repeating: 0, count: count)
                manager.getLineFragmentInsertionPoints(forCharacterAt: character, alternatePositions: false,
                    inDisplayOrder: false, positions: &positions, characterIndexes: &indexes)
                if let index = indexes.firstIndex(of: selection.location) { x = line.minX + positions[index] }
            }
        }
        return CGRect(x: x, y: line.minY + (style == .display ? 12.6 : 0),
                      width: style == .display ? 3 : 2, height: style == .display ? 56 : style.lineHeight)
    }

    override func mouseDown(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        point.y -= textContainerOrigin.y
        for index in content.blocks.indices where content.blocks[index].style == .task {
            let rect = blockRect(at: content.range(of: index).location)
            if CGRect(x: 8, y: rect.minY, width: 24, height: rect.height).contains(point) {
                let selection = selectedRange()
                edit { content in content.toggleTask(at: index); return selection }
                return
            }
        }
        typingEnd = nil
        super.mouseDown(with: event)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var rect = rect
        let style = content.blocks[content.position(at: selectedRange().location).block].style
        rect.size.width = style == .display ? 3 : 2
        if style == .display { rect.origin.y += 10; rect.size.height = 56 }
        else { rect.size.height = style.lineHeight }
        super.drawInsertionPoint(in: rect, color: NotePageTypography.textColor, turnedOn: flag)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard content.blocks.first?.text.isEmpty == true, content.blocks.first?.style == .display else { return }
        var attributes = NotePageTypography.attributes(heading: true)
        attributes[.foregroundColor] = NotePageTypography.placeholderColor
        let origin = CGPoint(x: textContainerOrigin.x + 8, y: textContainerOrigin.y)
        NSAttributedString(string: "a new note", attributes: attributes).draw(at: origin)
    }
}
