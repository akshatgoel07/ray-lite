import AppKit

@MainActor
final class BookmarksSidebar: NSView {
    private let panel = BookmarkSurface()
    private let header = BookmarkSurface()
    private let account = NSTextField(labelWithString: "Not connected / Bookmarks")
    private let refresh = BookmarkHeaderButton(title: "", target: nil, action: nil)
    private let add = BookmarkHeaderButton(title: "Add to Space", target: nil, action: nil)
    private let close = BookmarkHeaderButton(title: "", target: nil, action: nil)
    private let columns = [BookmarkSurface(), BookmarkSurface()]
    var onClose: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Bookmarks sidebar")
        panel.wantsLayer = true
        panel.setAccessibilityElement(true)
        panel.setAccessibilityRole(.group)
        panel.setAccessibilityLabel("Bookmarks panel")
        panel.layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.3
        panel.layer?.shadowRadius = 24
        addSubview(panel)
        header.wantsLayer = true
        header.setAccessibilityElement(true)
        header.setAccessibilityRole(.group)
        header.setAccessibilityLabel("Bookmarks header")
        header.layer?.backgroundColor = NSColor(srgbRed: 26 / 255, green: 29 / 255, blue: 30 / 255, alpha: 1).cgColor
        panel.addSubview(header)
        let title = NSMutableAttributedString(string: "Not connected / ", attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(white: 0.55, alpha: 1)
        ])
        title.append(NSAttributedString(string: "Bookmarks", attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(white: 0.94, alpha: 1)
        ]))
        account.attributedStringValue = title
        header.addSubview(account)
        refresh.symbol = "arrow.triangle.2.circlepath"
        refresh.setAccessibilityLabel("Refresh bookmarks")
        refresh.isEnabled = false
        add.setAccessibilityLabel("Add to Space")
        add.isEnabled = false
        close.symbol = "arrow.right"
        close.round = true
        close.setAccessibilityLabel("Close bookmarks")
        close.identifier = NSUserInterfaceItemIdentifier("Close bookmarks")
        close.target = self
        close.action = #selector(closeSidebar(_:))
        for button in [refresh, add, close] { header.addSubview(button) }
        for (index, column) in columns.enumerated() {
            column.setAccessibilityElement(true)
            column.setAccessibilityRole(.group)
            column.setAccessibilityLabel("Bookmarks column \(index + 1)")
            panel.addSubview(column)
        }
        let message = NSTextField(labelWithString: "No account connected.")
        message.font = .systemFont(ofSize: 14)
        message.textColor = NSColor(white: 0.94, alpha: 1)
        message.frame = CGRect(x: 0, y: 0, width: 324, height: 22)
        columns[0].addSubview(message)
        let detail = NSTextField(labelWithString: "Bookmarks require an account.")
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = NSColor(white: 0.55, alpha: 1)
        detail.frame = CGRect(x: 0, y: 28, width: 324, height: 22)
        columns[0].addSubview(detail)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let width = min(799, bounds.width)
        panel.frame = CGRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
        header.frame = CGRect(x: 0, y: 0, width: width, height: 64)
        account.frame = CGRect(x: 64, y: 20, width: max(150, width - 348), height: 24)
        refresh.frame = CGRect(x: width - 277, y: 16, width: 44, height: 32)
        add.frame = CGRect(x: width - 221, y: 16, width: 114, height: 32)
        close.frame = CGRect(x: width - 95, y: 16, width: 32, height: 32)
        let columnWidth = max(0, (width - 151) / 2)
        for (index, column) in columns.enumerated() {
            column.frame = CGRect(x: 64 + CGFloat(index) * (columnWidth + 24),
                                  y: 80, width: columnWidth, height: 50)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    @objc private func closeSidebar(_ sender: Any?) { onClose?() }
}

@MainActor
private final class BookmarkSurface: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class BookmarkHeaderButton: NSButton {
    var symbol: String?
    var round = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: isHighlighted ? 0.3 : 0.23, alpha: isEnabled ? 1 : 0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: round ? 16 : 12, yRadius: round ? 16 : 12).fill()
        let color = NSColor(white: 0.94, alpha: isEnabled ? 1 : 0.4)
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) {
            let tinted = NSImage(size: image.size)
            tinted.lockFocus()
            image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            CGRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: CGRect(x: (bounds.width - image.size.width) / 2,
                                  y: (bounds.height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
        } else {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: color]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2,
                                                y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10).stroke()
        }
    }
}
