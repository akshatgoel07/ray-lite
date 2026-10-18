import AppKit
import QuartzCore

@MainActor
final class NoteEditorSurface: NSView {
    private let surface = NoteEditorSurfaceLayer()
    private var caretTimer: Timer?
    private var lastRefresh = ProcessInfo.processInfo.systemUptime
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(textView: NoteTextView, scrollView: NSScrollView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = surface
        surface.textView = textView
        surface.scrollView = scrollView
        surface.host = self
        surface.needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        caretTimer?.invalidate()
        caretTimer = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ProcessInfo.processInfo.systemUptime - self.lastRefresh >= 0.5 else { return }
                self.surface.caretVisible.toggle()
                self.surface.setNeedsDisplay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        caretTimer = timer
    }

    func refresh() { lastRefresh = ProcessInfo.processInfo.systemUptime; surface.caretVisible = true; surface.contentsScale = window?.backingScaleFactor ?? 1; surface.setNeedsDisplay() }
}

@MainActor
private final class NoteEditorSurfaceLayer: CALayer {
    var caretVisible = true
    weak var textView: NoteTextView?
    weak var scrollView: NSScrollView?
    weak var host: NSView?

    override init() {
        super.init()
        actions = ["contents": NSNull()]
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }

    override func draw(in context: CGContext) {
        guard let textView, let scrollView, let host, let manager = textView.layoutManager,
              let container = textView.textContainer else { return }
        context.setFillColor(NotePageTransition.emptyColor.cgColor)
        context.fill(bounds)
        context.saveGState()
        let origin = textView.convert(textView.textContainerOrigin, to: host)
        context.translateBy(x: origin.x, y: origin.y)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        textView.textStorage?.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: textView.string.utf16.count)) { color, range, _ in
            guard let color = color as? NSColor else { return }
            let marked = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            color.setFill()
            manager.enumerateEnclosingRects(forGlyphRange: marked, withinSelectedGlyphRange: marked, in: container) { rect, _ in
                let background = CGRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: max(0, rect.height - 3))
                background.offsetBy(dx: origin.x, dy: origin.y).integral.offsetBy(dx: -origin.x, dy: -origin.y).fill()
            }
        }
        let selection = textView.selectedRange()
        if selection.length > 0 {
            let selected = manager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
            NSColor(srgbRed: 41 / 255, green: 44 / 255, blue: 45 / 255, alpha: 1).setFill()
            manager.enumerateEnclosingRects(forGlyphRange: selected, withinSelectedGlyphRange: selected, in: container) { rect, _ in rect.fill() }
        }
        manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        if textView.content.blocks.first?.text.isEmpty == true, textView.content.blocks.first?.style == .display {
            var attributes = NotePageTypography.attributes(heading: true)
            attributes[.foregroundColor] = NotePageTypography.placeholderColor
            NSAttributedString(string: "a new note", attributes: attributes).draw(at: CGPoint(x: 8, y: 0))
        }
        if caretVisible, selection.length == 0, textView.window?.firstResponder === textView {
            NotePageTypography.textColor.setFill()
            textView.insertionRect().fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        let documentHeight = scrollView.documentView?.bounds.height ?? bounds.height
        if documentHeight > bounds.height {
            let track: CGFloat = bounds.height - 224
            let height = max(28, track * bounds.height / documentHeight)
            let progress = scrollView.contentView.bounds.minY / max(1, documentHeight - bounds.height)
            context.setFillColor(NSColor(white: 0.64, alpha: 1).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: bounds.width - 21, y: 74 + (track - height) * progress, width: 6, height: height),
                                   cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()
        }
    }
}
