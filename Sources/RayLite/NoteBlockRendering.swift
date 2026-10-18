import AppKit

@MainActor
enum NoteBlockRendering {
    static func attributes(style: NoteBlockStyle, marks: Set<NoteMark> = [], link: String? = nil,
                           scale: CGFloat = 1, color: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        let color = color ?? NotePageTypography.textColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight * scale
        paragraph.maximumLineHeight = style.lineHeight * scale
        paragraph.paragraphSpacing = style == .display ? scale : 0
        paragraph.headIndent = CGFloat(style.prefixLength == 0 ? 0 : 32) * scale
        paragraph.tabStops = (1...20).map { NSTextTab(textAlignment: .left, location: CGFloat($0 * 33 + (style.prefixLength == 0 ? 0 : 32)) * scale) }
        paragraph.defaultTabInterval = 33 * scale
        var font = NotePageTypography.font(size: style.fontSize * scale,
                                          weight: marks.contains(.bold) ? .semibold : style.fontSize > 16 ? .medium : .regular)
        if marks.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var result: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color.withAlphaComponent(marks.contains(.strikethrough) ? 0.88 : 1),
            .paragraphStyle: paragraph, .baselineOffset: 4.4 * scale, .kern: (style == .display ? -0.4 : -0.25) * scale
        ]
        if marks.contains(.underline) || link != nil { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.strikethrough) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains(.highlight) { result[.backgroundColor] = NSColor(srgbRed: 0, green: 11 / 255, blue: 1, alpha: 1) }
        if let link, let url = URL(string: link) { result[.link] = url }
        return result
    }

    static func text(_ content: NoteContent, scale: CGFloat = 1,
                     color: NSColor? = nil) -> NSAttributedString {
        let color = color ?? NotePageTypography.textColor
        let result = NSMutableAttributedString(string: "")
        for (index, block) in content.blocks.enumerated() {
            let base = attributes(style: block.style, scale: scale, color: color)
            if block.style.prefixLength > 0 {
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NoteBlockAttachmentCell(style: block.style, checked: block.checked, scale: scale)
                let marker = NSMutableAttributedString(attachment: attachment)
                marker.addAttributes(base, range: NSRange(location: 0, length: marker.length))
                result.append(marker)
                result.append(NSAttributedString(string: "\u{200b}", attributes: base))
            }
            for run in block.runs {
                result.append(NSAttributedString(string: run.text,
                    attributes: attributes(style: block.style, marks: run.marks, link: run.link, scale: scale, color: color)))
            }
            if index < content.blocks.count - 1 { result.append(NSAttributedString(string: "\n", attributes: base)) }
        }
        return result
    }
}

@MainActor
private final class NoteBlockAttachmentCell: NSTextAttachmentCell {
    let style: NoteBlockStyle
    let checked: Bool
    let scale: CGFloat

    init(style: NoteBlockStyle, checked: Bool, scale: CGFloat) {
        self.style = style
        self.checked = checked
        self.scale = scale
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError() }

    override func cellSize() -> NSSize { NSSize(width: 32 * scale, height: 18 * scale) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -3 * scale) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if style == .list {
            NSColor(srgbRed: 54 / 255, green: 64 / 255, blue: 68 / 255, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: cellFrame.minX + 6 * scale, y: cellFrame.midY - 3 * scale,
                                       width: 6 * scale, height: 6 * scale)).fill()
        } else {
            let rect = CGRect(x: cellFrame.minX, y: cellFrame.minY, width: 18 * scale, height: 18 * scale)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5 * scale, yRadius: 5 * scale)
            (checked ? NotePageTypography.textColor : NSColor(srgbRed: 61 / 255, green: 66 / 255, blue: 68 / 255, alpha: 1)).setFill()
            path.fill()
            if !checked {
                NSColor.white.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 0.5 * scale
                path.stroke()
            }
        }
    }
}
