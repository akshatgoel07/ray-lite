import AppKit
import QuartzCore

@MainActor
final class NoteSelectionToolbar: NSView {
    var onFormat: ((NoteMark?) -> Void)?
    private var visible = false
    private let marks: [NoteMark?] = [.highlight, .bold, .italic, .underline, .strikethrough, nil]
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        identifier = NSUserInterfaceItemIdentifier("Note selection toolbar")
        layer?.backgroundColor = NSColor(srgbRed: 29 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 24
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        let names = ["highlighter", "bold", "italic", "underline", "strikethrough", "eraser"]
        let labels = ["Highlight", "Bold", "Italic", "Underline", "Strikethrough", "Remove format"]
        for index in names.indices {
            let button = NSButton(frame: CGRect(x: 10 + index * 62, y: 0, width: 62, height: 58))
            button.title = ""
            button.image = NSImage(systemSymbolName: names[index], accessibilityDescription: labels[index])?
                .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
            button.contentTintColor = NSColor(srgbRed: 164 / 255, green: 168 / 255, blue: 169 / 255, alpha: 1)
            button.isBordered = false
            button.tag = index
            button.target = self
            button.action = #selector(format(_:))
            button.identifier = NSUserInterfaceItemIdentifier("Note " + labels[index])
            button.setAccessibilityLabel(labels[index])
            addSubview(button)
        }
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    @objc private func format(_ sender: NSButton) { onFormat?(marks[sender.tag]) }

    func updateSelection(_ runs: [NoteRun]) {
        let clear = subviews.compactMap { $0 as? NSButton }.last
        clear?.isEnabled = runs.contains { !$0.marks.isEmpty || $0.link != nil }
    }

    func place(in bounds: CGRect) { frame = CGRect(x: (bounds.width - 392) / 2, y: bounds.height - 90, width: 392, height: 58) }

    func displayTools(_ value: Bool, in bounds: CGRect) {
        guard value != visible else { return }
        visible = value
        place(in: bounds)
        layer?.removeAllAnimations()
        isHidden = !value
        guard value, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.94
        scale.toValue = 1
        let position = CABasicAnimation(keyPath: "position.y")
        position.fromValue = bounds.height + 29
        position.toValue = layer.position.y
        let group = CAAnimationGroup()
        group.animations = [scale, position]
        group.duration = 1.0 / 3.0
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        layer.add(group, forKey: "note.toolbar")
    }
}
