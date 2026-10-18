import AppKit
import QuartzCore

public enum ItemKind: String, Sendable {
    case note, image, video, webClip
}

@MainActor
public struct CanvasItem: Identifiable, Sendable {
    public let id: UUID
    public var kind: ItemKind
    public var point: CGPoint
    public var size: CGSize
    public var text: String?
    public var videoURL: URL?

    public init(id: UUID = UUID(), kind: ItemKind, point: CGPoint, size: CGSize,
                text: String? = nil, videoURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.point = point
        self.size = size
        self.text = text
        self.videoURL = videoURL
    }
}

@MainActor
public final class CanvasItemView: NSView {
    override public var acceptsFirstResponder: Bool { canvas != nil }

    override public func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        canvas?.select([id])
        canvas?.updateSelectionOverlay()
        return accepted
    }

    override public func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        DispatchQueue.main.async { [weak self] in self?.canvas?.updateSelectionOverlay() }
        return accepted
    }

    override public func keyDown(with event: NSEvent) { canvas?.keyDown(with: event) }

    override public func keyUp(with event: NSEvent) { canvas?.keyUp(with: event) }

    static let cornerRadius: CGFloat = 12
    public let id: UUID
    private let image: ImageAttachment?
    private let cardKind: ItemKind
    private var thumbnailPixels = 0
    private(set) var thumbnailSize = CGSize.zero
    weak var canvas: CanvasView?
    public var baseItem: (id: UUID, size: CGSize) {
        (id, canvas?.notes.first(where: { $0.id == id })?.frame.size ?? frame.size)
    }
    public let container = CALayer()
    public let shadowShapeLayer = CALayer()
    public let contentLayer = CALayer()
    public var isSelected: Bool {
        get { canvas?.selection.contains(id) ?? false }
        set { canvas?.setSelected(id, selected: newValue) }
    }

    override public var frame: NSRect {
        didSet {
            needsLayout = true
            canvas?.updateFrame(id: id, frame: frame)
        }
    }

    public init(item: CanvasItem) {
        id = item.id
        cardKind = item.kind
        image = nil
        super.init(frame: CGRect(origin: item.point, size: item.size))
        wantsLayer = true
        layer?.addSublayer(shadowShapeLayer)
        layer?.addSublayer(container)
        container.addSublayer(contentLayer)
        rebuildContent(item: item)
        applyColor()
        needsLayout = true
    }

    public init(note: NoteRecord) {
        id = note.id
        cardKind = note.kind
        image = note.image
        super.init(frame: note.frame)
        wantsLayer = true
        layer?.addSublayer(shadowShapeLayer)
        layer?.addSublayer(container)
        container.addSublayer(contentLayer)
        if image == nil { contentLayer.addSublayer(NoteTextLayer(content: note.content)) }
        applyColor()
        needsLayout = true
    }

    required init?(coder: NSCoder) { nil }

    override public func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        container.cornerRadius = (cardKind == .image || cardKind == .video)
            ? (AppPreferences.shared.cornerStyle == .round ? 12 : 0) : Self.cornerRadius
        container.masksToBounds = true
        contentLayer.frame = container.bounds
        shadowShapeLayer.frame = bounds
        shadowShapeLayer.shadowPath = CGPath(roundedRect: shadowShapeLayer.bounds,
                                             cornerWidth: container.cornerRadius, cornerHeight: container.cornerRadius, transform: nil)
        shadowShapeLayer.shadowColor = NSColor.black.cgColor
        shadowShapeLayer.shadowOpacity = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0 : 0.12
        shadowShapeLayer.shadowRadius = 3
        shadowShapeLayer.shadowOffset = CGSize(width: 0, height: -1)
        for child in contentLayer.sublayers ?? [] {
            child.frame = child is NoteTextLayer
                ? CGRect(x: 20, y: 0, width: max(0, bounds.width - 40), height: max(0, bounds.height - 30)) : contentLayer.bounds
            child.setNeedsLayout()
            child.layoutIfNeeded()
        }
        updateContentsScale()
        refreshImageThumbnail()
        canvas?.configureNoteCard(self)
        CATransaction.commit()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimations() }
        applyColor()
        needsLayout = true
    }

    func fadeIn() {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        CATransaction.commit()
        SpringCore.shared.fade(layer, to: 1, duration: 0.14, key: "rayLite.noteFade")
    }

    func interruptFade() {
        guard let layer, layer.animation(forKey: "rayLite.noteFade") != nil else { return }
        SpringCore.shared.cancel(layer, keyPath: "opacity", behavior: .keepCurrentValue)
        SpringCore.shared.fade(layer, to: 1, duration: 0.1, key: "rayLite.inputOpacity")
    }

    func stopAnimations() {
        guard let layer else { return }
        SpringCore.shared.cancel(layer, keyPath: "opacity", behavior: .keepCurrentValue)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        CATransaction.commit()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
        needsLayout = true
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        for current in [layer, container, shadowShapeLayer, contentLayer].compactMap({ $0 }) {
            current.contentsScale = scale
        }
        for child in contentLayer.sublayers ?? [] {
            child.contentsScale = scale
            child.sublayers?.forEach { $0.contentsScale = scale }
        }
    }

    public func applyColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            contentLayer.backgroundColor = (dark
                ? (cardKind == .note ? NSColor(srgbRed: 29 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1)
                    : NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1)) : NSColor.white).cgColor
            container.borderWidth = image == nil ? 0.5 : 0
            if image != nil { contentLayer.backgroundColor = nil }
            container.borderColor = NSColor.white.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.6 : 0.07).cgColor
            if let note = canvas?.notes.first(where: { $0.id == id }) {
                for child in contentLayer.sublayers ?? [] { (child as? NoteTextLayer)?.setContent(note.content, color: dark ? NotePageTypography.textColor : .black) }
            }
        }
    }

    func refreshImageThumbnail() {
        guard let image else { return }
        let scale = (window?.backingScaleFactor ?? 1) * (canvas?.magnification ?? 1)
        let pixels = max(1, Int(ceil(max(bounds.width, bounds.height) * scale)))
        guard pixels != thumbnailPixels else { return }
        guard let thumbnail = image.thumbnail(maxPixels: pixels) else { return }
        thumbnailPixels = pixels
        thumbnailSize = CGSize(width: thumbnail.width, height: thumbnail.height)
        contentLayer.contents = thumbnail
        contentLayer.contentsGravity = .resizeAspect
        contentLayer.minificationFilter = .trilinear
    }

    private func rebuildContent(item: CanvasItem) {
        contentLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        switch item.kind {
        case .note:
            contentLayer.addSublayer(NoteTextLayer(text: item.text ?? ""))
        case .video:
            if let url = item.videoURL {
                contentLayer.addSublayer(VideoPlayerItem(assetURL: url))
            }
        case .image:
            break
        case .webClip:
            let placeholder = CALayer()
            placeholder.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
            contentLayer.addSublayer(placeholder)
        }
    }
}

@MainActor
public final class NoteTextLayer: CALayer {
    private var textLayer: CATextLayer? { sublayers?.first as? CATextLayer }

    public convenience init(text: String) { self.init(content: NoteContent(plainText: text)) }

    public init(content: NoteContent) {
        super.init()
        let textLayer = NotePreviewTextLayer()
        textLayer.actions = ["contents": NSNull()]
        textLayer.isWrapped = true
        textLayer.truncationMode = .none
        masksToBounds = true
        addSublayer(textLayer)
        setContent(content)
    }

    override public init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }

    static func fittedFrame(_ frame: CGRect, text: String) -> CGRect { frame }

    public func setText(_ text: String, color: NSColor? = nil) {
        setContent(NoteContent(plainText: text), color: color)
    }

    public func setContent(_ content: NoteContent, color: NSColor? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer?.string = NoteBlockRendering.text(content, scale: 1 / 6, color: color ?? NotePageTypography.textColor)
        setNeedsLayout()
        CATransaction.commit()
    }

    override public func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer?.frame = bounds
        textLayer?.contentsScale = contentsScale
        CATransaction.commit()
    }
}

@MainActor
private final class NotePreviewTextLayer: CATextLayer {
    override func draw(in context: CGContext) {
        guard let text = string as? NSAttributedString else { return }
        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: glyphs, at: .zero)
        manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}

@MainActor
final class NoteAccessibilityElement: NSAccessibilityElement {
    let id: UUID
    private weak var canvas: CanvasView?

    init(id: UUID, canvas: CanvasView) {
        self.id = id
        self.canvas = canvas
        super.init()
        setAccessibilityRole(.group)
        setAccessibilityParent(canvas)
        setAccessibilityIdentifier(id.uuidString)
        setAccessibilityHelp("Press to select. Open to edit.")
    }

    private var note: NoteRecord? { canvas?.notes.first { $0.id == id } }

    override func accessibilityLabel() -> String? {
        guard let note else { return nil }
        return note.text.isEmpty ? "Empty note" : note.text
    }

    override func accessibilityValue() -> Any? { note?.text ?? "" }

    override func isAccessibilitySelected() -> Bool { canvas?.selection.contains(id) ?? false }

    override func isAccessibilityFocused() -> Bool { (canvas?.window?.firstResponder as? CanvasItemView)?.id == id }

    override func setAccessibilityFocused(_ focused: Bool) {
        if focused { canvas?.focusNote(id) }
    }

    override func accessibilityFrame() -> NSRect {
        guard let canvas, let note, let window = canvas.window else { return .zero }
        return window.convertToScreen(canvas.convert(canvas.viewRect(fromCanvas: note.frame), to: nil))
    }

    override func accessibilityPerformPress() -> Bool {
        guard let canvas, note != nil else { return false }
        canvas.focusNote(id)
        return true
    }

    override func accessibilityPerformPick() -> Bool {
        guard let canvas, note != nil else { return false }
        canvas.beginEditing(id)
        return true
    }
}
