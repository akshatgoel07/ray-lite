import AppKit
import QuartzCore

@MainActor
enum NotePageTypography {
    static let textColor = NSColor(srgbRed: 245 / 255, green: 248 / 255, blue: 249 / 255, alpha: 1)
    static let placeholderColor = NSColor(srgbRed: 51 / 255, green: 55 / 255, blue: 55 / 255, alpha: 1)

    static func headingRange(in text: String) -> NSRange {
        let text = text as NSString
        let newline = text.range(of: "\n")
        return NSRange(location: 0, length: newline.location == NSNotFound ? text.length : NSMaxRange(newline))
    }

    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        AppPreferences.shared.noteFont == .mono
            ? .monospacedSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
    }

    static func attributes(heading: Bool) -> [NSAttributedString.Key: Any] {
        NoteBlockRendering.attributes(style: heading ? .display : .body)
    }

    static func text(_ text: String) -> NSAttributedString {
        NoteBlockRendering.text(NoteContent(plainText: text))
    }
}

@MainActor
final class NoteEditor: NSView, NSTextViewDelegate {
    let noteID: UUID
    let scrollView = NotePageScrollView()
    let textView = NoteTextView()
    let backControl = NSButton()
    private(set) var destination = NotePageTransition.Destination.page
    private let document = NotePageDocument()
    private lazy var surface = NoteEditorSurface(textView: textView, scrollView: scrollView)
    private let toolbar = NoteSelectionToolbar()
    private let blockControl = NoteBlockControl()
    private var tracking: NSTrackingArea?
    var content: NoteContent { textView.content }
    private let transition = NotePageTransition()
    private let transitionHost = NSView()
    private var completion: DispatchWorkItem?
    var isTransitioning: Bool { !transitionHost.isHidden }
    var onExit: (() -> Bool)? {
        didSet { textView.onExit = onExit }
    }
    var onReturn: (() -> Void)?
    var onOutsideClick: (() -> Void)?

    override var isFlipped: Bool { true }

    init(note: NoteRecord) {
        noteID = note.id
        super.init(frame: .zero)
        wantsLayer = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NotePageTransition.emptyColor
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerKnobStyle = .light
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init()
        scrollView.wantsLayer = true
        scrollView.contentView.drawsBackground = false
        textView.load(note.content)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = self
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 41 / 255, green: 44 / 255, blue: 45 / 255, alpha: 1),
                                           .foregroundColor: NotePageTypography.textColor]
        textView.linkTextAttributes = [.foregroundColor: NotePageTypography.textColor, .underlineStyle: 1]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        textView.backgroundColor = NotePageTransition.emptyColor
        textView.insertionPointColor = NotePageTypography.textColor
        textView.setAccessibilityLabel("Note text")
        document.onMouseDown = { [weak self] event in
            guard let self else { return }
            let point = self.document.convert(event.locationInWindow, from: nil)
            if point.x < self.textView.frame.minX - 96 || point.x > self.textView.frame.maxX {
                self.onOutsideClick?()
            } else {
                self.mouseMoved(with: event)
                self.window?.makeFirstResponder(self.textView)
            }
        }
        document.addSubview(textView)
        scrollView.documentView = document
        addSubview(scrollView)
        addSubview(surface)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        transitionHost.wantsLayer = true
        transitionHost.layer = transition
        addSubview(transitionHost)
        backControl.title = ""
        backControl.identifier = NSUserInterfaceItemIdentifier("Back to board")
        backControl.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        backControl.contentTintColor = NotePageTypography.textColor
        backControl.isBordered = false
        backControl.wantsLayer = true
        backControl.layer?.backgroundColor = NSColor(srgbRed: 38 / 255, green: 41 / 255, blue: 43 / 255, alpha: 1).cgColor
        backControl.layer?.cornerRadius = 22
        backControl.layer?.borderWidth = 0.5
        backControl.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        backControl.target = self
        backControl.action = #selector(returnToBoard(_:))
        backControl.setAccessibilityLabel("Back to board")
        backControl.cell?.setAccessibilityLabel("Back to board")
        backControl.toolTip = "Back to board"
        addSubview(backControl)
        toolbar.onFormat = { [weak self] mark in
            guard let self else { return }
            self.textView.applyFormat(mark, collapse: true)
            self.window?.makeFirstResponder(self.textView)
        }
        addSubview(toolbar)
        blockControl.onStyle = { [weak self] style, index in self?.textView.applyBlockStyle(style, at: index) }
        addSubview(blockControl)
        textView.onContentChange = { [weak self] in
            self?.blockControl.dismissMenu()
            self?.resizeDocument()
            self?.updateSelection()
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { nil }

    @objc private func returnToBoard(_ sender: Any?) { _ = onExit?() }

    func textDidChange(_ notification: Notification) {
        textView.needsDisplay = true
        if transitionHost.isHidden { layer?.backgroundColor = pageColor.cgColor }
    }

    private var pageColor: NSColor {
        NotePageTransition.emptyColor
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.selectionChanged()
        updateSelection()
    }

    @objc private func scrollChanged(_ notification: Notification) {
        if !blockControl.menuVisible { blockControl.isHidden = true }
        surface.refresh()
    }

    private func updateSelection() {
        surface.refresh()
        let selection = textView.selectedRange()
        toolbar.updateSelection(selection.length > 0 ? textView.content.selectedRuns(in: selection) : [])
        toolbar.displayTools(selection.length > 0, in: bounds)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard transitionHost.isHidden, !blockControl.menuVisible else { return }
        var point = textView.convert(event.locationInWindow, from: nil)
        point.y -= textView.textContainerOrigin.y
        guard point.x >= -104, point.x <= textView.bounds.width,
              point.y >= 0, point.y <= textView.bounds.height, let manager = textView.layoutManager,
              let container = textView.textContainer else { blockControl.isHidden = true; return }
        let glyph = manager.glyphIndex(for: point, in: container)
        let character = manager.numberOfGlyphs > 0 ? manager.characterIndexForGlyph(at: min(glyph, manager.numberOfGlyphs - 1)) : 0
        let index = textView.content.position(at: character).block
        let range = textView.content.range(of: index)
        let rect = textView.blockRect(at: range.location)
        let origin = convert(CGPoint(x: textView.frame.minX - 96, y: textView.frame.minY + textView.textContainerOrigin.y + rect.minY), from: document)
        blockControl.show(index: index, style: textView.content.blocks[index].style,
                          frame: CGRect(x: origin.x, y: origin.y - 2.4, width: 52, height: 38))
    }

    override func mouseExited(with event: NSEvent) {
        if !blockControl.menuVisible { blockControl.isHidden = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrollView.frame = bounds
        transitionHost.frame = bounds
        surface.frame = bounds
        surface.refresh()
        textView.textContainerInset = NSSize(width: 0, height: -8.6)
        resizeDocument()
        backControl.frame = CGRect(x: 16, y: 59, width: 44, height: 44)
        toolbar.place(in: bounds)
        CATransaction.commit()
    }

    private func resizeDocument() {
        let width = min(616, max(32, bounds.width - 32))
        textView.frame = CGRect(x: (bounds.width - width) / 2, y: 176, width: width,
                               height: max(68, textView.frame.height))
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let height = max(68, ceil(layout.usedRect(for: container).height))
        textView.setFrameSize(CGSize(width: width, height: height))
        document.setFrameSize(CGSize(width: bounds.width, height: max(bounds.height, height + textView.frame.minY + textView.textContainerOrigin.y + 416.33375)))
    }

    func present(_ destination: NotePageTransition.Destination, from card: CGRect, scale: CGFloat,
                 initial: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        completion?.cancel()
        self.destination = destination
        layoutSubtreeIfNeeded()
        if initial || transitionHost.isHidden {
            transition.prepare(textView: textView, page: bounds, card: card, scale: scale,
                               at: initial ? .board : .page)
        }
        transitionHost.isHidden = false
        surface.isHidden = true
        scrollView.isHidden = true
        textView.isEditable = destination == .page
        layer?.backgroundColor = nil
        if initial { backControl.layer?.opacity = 0 }
        let duration = transition.animate(to: destination, page: bounds, card: card, scale: scale)
        if let layer = backControl.layer {
            SpringCore.shared.fade(layer, to: destination == .page ? 1 : 0,
                                   duration: min(duration, 0.2), key: "rayLite.noteBack")
        }
        let completion = DispatchWorkItem { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            if self.destination == .page {
                self.scrollView.isHidden = false
                self.surface.isHidden = false
                self.surface.refresh()
                self.transitionHost.isHidden = true
                self.layer?.backgroundColor = self.pageColor.cgColor
                self.textView.needsDisplay = true
                self.scrollView.display()
            } else {
                self.onReturn?()
            }
        }
        self.completion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }

    func stopTransition() {
        completion?.cancel()
        completion = nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseMoved(with: event)
        window?.makeFirstResponder(textView)
    }

    override func cancelOperation(_ sender: Any?) {}
}

@MainActor
private final class NotePageDocument: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?(event) }
}

@MainActor
final class NotePageScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        let maximum = max(0, documentView.bounds.height - contentView.bounds.height)
        let y = max(0, min(maximum, contentView.bounds.minY - delta))
        contentView.scroll(to: CGPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }
}
