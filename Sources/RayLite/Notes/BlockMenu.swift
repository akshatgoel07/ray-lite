import AppKit

@MainActor
final class NoteBlockControl: NSButton {
    var onStyle: ((NoteBlockStyle, Int) -> Void)?
    private var blockIndex = 0
    private var style = NoteBlockStyle.body
    private weak var overlay: NoteBlockMenuOverlay?
    var menuVisible: Bool { overlay != nil }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 40 / 255, green: 44 / 255, blue: 45 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 16
        target = self
        action = #selector(openMenu(_:))
        identifier = NSUserInterfaceItemIdentifier("Note block style")
        setAccessibilityLabel("Block style")
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func show(index: Int, style: NoteBlockStyle, frame: CGRect) {
        blockIndex = index
        self.style = style
        self.frame = frame
        isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 116 / 255, green: 121 / 255, blue: 123 / 255, alpha: 1).setFill()
        for x in [21.0, 29.0] { NSBezierPath(ovalIn: CGRect(x: x, y: 17, width: 3, height: 3)).fill() }
    }

    override func mouseDown(with event: NSEvent) {
        var dragged = false
        while let next = VerificationRuntime.nextPointerEvent() {
            if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 4 { dragged = true }
            if next.type == .leftMouseUp {
                if !dragged { openMenu(self) } else { isHidden = true }
                return
            }
        }
    }

    @objc private func openMenu(_ sender: Any?) {
        guard let parent = superview, overlay == nil else { return }
        let overlay = NoteBlockMenuOverlay(frame: parent.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NotePageTransition.emptyColor.withAlphaComponent(0.55).cgColor
        overlay.autoresizingMask = [.width, .height]
        let menu = NSView(frame: CGRect(x: frame.midX, y: frame.midY, width: 312, height: 304))
        menu.wantsLayer = true
        menu.clipsToBounds = false
        menu.layer?.backgroundColor = NSColor(srgbRed: 29 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1).cgColor
        menu.layer?.cornerRadius = 24
        menu.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        menu.layer?.borderWidth = 0.5
        menu.layer?.shadowColor = NSColor.black.cgColor
        menu.layer?.shadowOpacity = 0.5
        menu.layer?.shadowRadius = 40
        menu.layer?.shadowOffset = CGSize(width: 0, height: -20)
        let separator = NSView(frame: CGRect(x: 24, y: 107, width: 264, height: 0.5))
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        menu.addSubview(separator)
        overlay.addSubview(menu)
        let offsets: [CGFloat] = [8, 53, 98, 143, 206, 251]
        for (index, item) in NoteBlockStyle.allCases.enumerated() {
            let row = NoteBlockStyleButton(style: item, frame: CGRect(x: 8, y: 304 - offsets[index] - 45, width: 296, height: 45))
            row.isEnabled = item != style
            row.target = self
            row.action = #selector(chooseStyle(_:))
            menu.addSubview(row)
        }
        parent.addSubview(overlay)
        self.overlay = overlay
    }

    func dismissMenu() {
        overlay?.removeFromSuperview()
        isHidden = true
    }

    @objc private func chooseStyle(_ sender: NoteBlockStyleButton) {
        dismissMenu()
        onStyle?(sender.style, blockIndex)
    }
}

@MainActor
private final class NoteBlockMenuOverlay: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { removeFromSuperview() }
}

@MainActor
private final class NoteBlockStyleButton: NSButton {
    let style: NoteBlockStyle

    init(style: NoteBlockStyle, frame: CGRect) {
        self.style = style
        super.init(frame: frame)
        title = style.title
        identifier = NSUserInterfaceItemIdentifier("Note style " + style.title)
        setAccessibilityLabel(style.title)
        isBordered = false
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color = NotePageTypography.textColor.withAlphaComponent(isEnabled ? 1 : 0.3)
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        NSAttributedString(string: style.title, attributes: [.font: font, .foregroundColor: color])
            .draw(at: CGPoint(x: 52, y: 15))
        if let number = NoteBlockStyle.allCases.firstIndex(of: style), number < 4 {
            NSAttributedString(string: String(format: "%02d", number + 1), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: color])
                .draw(at: CGPoint(x: 18, y: 15))
        } else if let image = NSImage(systemSymbolName: style == .list ? "list.bullet" : "square", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium).applying(.init(paletteColors: [color]))) {
            image.draw(in: CGRect(x: 18, y: 14, width: 18, height: 18))
        }
        let shortcut: String
        switch style {
        case .display: shortcut = "#"
        case .headline: shortcut = "##"
        case .subheader: shortcut = "###"
        case .body: shortcut = "⌘4"
        case .list: shortcut = "⌘L"
        case .task: shortcut = "⌘T"
        }
        let label = NSAttributedString(string: shortcut, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(0.35)])
        label.draw(at: CGPoint(x: bounds.width - 18 - label.size().width, y: 15))
    }
}
