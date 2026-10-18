import AppKit
import QuartzCore

@MainActor
final class NotePageTransition: CALayer {
    enum Destination { case board, page }

    static let pageColor = NSColor(srgbRed: 23 / 255, green: 26 / 255, blue: 27 / 255, alpha: 1)
    static let emptyColor = pageColor
    static let cardColor = NSColor(srgbRed: 29 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1)

    static func animation(keyPath: String, to value: Any, destination: Destination) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.toValue = value
        animation.duration = destination == .page ? 0.55 : 0.467
        animation.timingFunction = destination == .page
            ? CAMediaTimingFunction(controlPoints: 0.72, 0, 0.15, 1)
            : CAMediaTimingFunction(controlPoints: 0.05, 0.85, 0.2, 1)
        return animation
    }

    private let sheet = CALayer()
    private let content = CATextLayer()
    private var contentPoint = CGPoint.zero
    private var empty = false

    override init() {
        super.init()
        anchorPoint = .zero
        isGeometryFlipped = false
        name = "Note page transition"
        sheet.name = "Note page fill"
        sheet.anchorPoint = .zero
        sheet.masksToBounds = true
        sheet.isGeometryFlipped = false
        content.name = "Note page text"
        content.anchorPoint = .zero
        content.isWrapped = true
        sheet.addSublayer(content)
        addSublayer(sheet)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }

    func prepare(textView: NSTextView, page: CGRect, card: CGRect, scale: CGFloat, at destination: Destination) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = page
        empty = textView.string.isEmpty
        if empty {
            var attributes = NotePageTypography.attributes(heading: true)
            attributes[.foregroundColor] = NotePageTypography.placeholderColor
            content.string = NSAttributedString(string: "a new note", attributes: attributes)
        } else {
            content.string = textView.textStorage?.copy() as? NSAttributedString
        }
        let origin = textView.convert(textView.textContainerOrigin, to: textView.enclosingScrollView?.superview)
        contentPoint = CGPoint(x: origin.x + 8, y: origin.y)
        content.bounds = CGRect(x: 0, y: 0, width: max(1, textView.bounds.width - 16),
                                height: max(page.height, textView.frame.height))
        content.contentsScale = textView.window?.backingScaleFactor ?? 2
        for (layer, keyPath, value) in values(destination, page: page, card: card, scale: scale) {
            layer.setValue(value, forKeyPath: keyPath)
        }
        CATransaction.commit()
    }

    private func values(_ destination: Destination, page: CGRect, card: CGRect, scale: CGFloat) -> [(CALayer, String, Any)] {
        let expanded = destination == .page
        let size = expanded ? page.size : card.size
        let textScale = expanded ? 1 : scale / 6
        let textPoint = expanded ? contentPoint : CGPoint(x: 20 * scale, y: 30 * scale)
        return [(sheet, "bounds", NSValue(rect: CGRect(origin: .zero, size: size))),
                (sheet, "position", NSValue(point: expanded ? .zero : CGPoint(x: card.minX, y: page.height - card.maxY))),
                (sheet, "cornerRadius", expanded ? 0 : BoardSurface.noteCornerRadius * scale),
                (sheet, "backgroundColor", (expanded ? Self.pageColor : Self.cardColor).cgColor),
                (content, "position", NSValue(point: CGPoint(x: textPoint.x, y: size.height - textPoint.y - content.bounds.height * textScale))),
                (content, "transform", NSValue(caTransform3D: CATransform3DMakeScale(textScale, textScale, 1))),
                (content, "opacity", empty && !expanded ? Float(0) : Float(1))]
    }

    @discardableResult
    func animate(to destination: Destination, page: CGRect, card: CGRect, scale: CGFloat) -> TimeInterval {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var duration: TimeInterval = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, keyPath, value) in values(destination, page: page, card: card, scale: scale) {
            if reduceMotion {
                layer.setValue(value, forKeyPath: keyPath)
            } else {
                let animation = Self.animation(keyPath: keyPath, to: value, destination: destination)
                duration = animation.duration
                SpringCore.shared.add(animation, to: layer, key: "rayLite.notePage.\(keyPath)")
            }
        }
        CATransaction.commit()
        return duration
    }
}
