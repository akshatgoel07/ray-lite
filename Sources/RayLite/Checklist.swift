import AppKit
import QuartzCore

enum ChecklistTask: String, CaseIterable {
    case createNote, createSticky, colors, addImage, imageNote
    case createStack, openStack, createFolder, addToFolder, scratchPad

    var label: String {
        switch self {
        case .createNote: return "Create a Note"
        case .createSticky: return "Create a Sticky"
        case .colors: return "Colors"
        case .addImage: return "Add an Image"
        case .imageNote: return "Write a note to an Image"
        case .createStack: return "Create a Stack"
        case .openStack: return "Open a Stack"
        case .createFolder: return "Create a Folder"
        case .addToFolder: return "Add to a Folder"
        case .scratchPad: return "Write in the Scratch Pad"
        }
    }

    var shortcut: String {
        switch self {
        case .createNote: return "⌘ N"
        case .createSticky: return "⇧⌘ N"
        case .createStack: return "⌘ S"
        case .scratchPad: return "⌥ Space"
        default: return ""
        }
    }

    var isAvailable: Bool { self == .createNote }
}

@MainActor
final class ChecklistProgress {
    private let defaults: UserDefaults
    private let key = "checklistCompletedTasks"
    var onChange: (() -> Void)?

    init(defaults: UserDefaults) { self.defaults = defaults }

    var completed: Set<ChecklistTask> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(ChecklistTask.init(rawValue:))
            .filter(\.isAvailable))
    }

    var counter: String { String(format: "%02d/10", completed.count) }

    func complete(_ task: ChecklistTask) {
        guard task.isAvailable else { return }
        var tasks = completed
        guard tasks.insert(task).inserted else { return }
        defaults.set(ChecklistTask.allCases.filter(tasks.contains).map(\.rawValue), forKey: key)
        onChange?()
    }
}

@MainActor
final class ChecklistSidebar: NSView {
    private let progress: ChecklistProgress
    private let header = NSView()
    private let scroll = NSScrollView()
    private let list = ChecklistList()
    private var rows: [ChecklistRow] = []
    private var colorsExpanded = true
    var onClose: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: CGRect, progress: ChecklistProgress) {
        self.progress = progress
        super.init(frame: frame)
        autoresizingMask = [.minXMargin, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Checklist")
        setAccessibilityElement(true)
        list.setAccessibilityRole(.list)
        list.setAccessibilityElement(true)
        header.wantsLayer = true
        header.frame = CGRect(x: 24, y: 0, width: frame.width - 48, height: 64)
        header.layer?.backgroundColor = NSColor(srgbRed: 26 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1).cgColor
        addSubview(header)
        let title = NSTextField(labelWithString: "")
        let heading = NSMutableAttributedString(string: "Checklist / ", attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white.withAlphaComponent(0.5)
        ])
        heading.append(NSAttributedString(string: "Learn the basics", attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]))
        title.attributedStringValue = heading
        title.frame = CGRect(x: 12, y: 17, width: 280, height: 24)
        title.autoresizingMask = [.maxXMargin]
        header.addSubview(title)
        let close = ChecklistCloseButton()
        close.frame = CGRect(x: frame.width - 92, y: 16, width: 32, height: 32)
        close.autoresizingMask = [.minXMargin]
        close.target = self
        close.action = #selector(closeSidebar(_:))
        header.addSubview(close)
        scroll.drawsBackground = false
        scroll.documentView = list
        addSubview(scroll)
        for task in ChecklistTask.allCases {
            let row = ChecklistRow(task: task)
            if task == .colors {
                row.target = self
                row.action = #selector(toggleColors(_:))
            }
            list.addSubview(row)
            rows.append(row)
        }
        list.setAccessibilityChildren(rows)
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func refresh() {
        for row in rows {
            row.completed = progress.completed.contains(row.task)
            row.setAccessibilityValue(row.completed ? "Complete" : "Incomplete")
            row.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        header.frame = CGRect(x: 24, y: 0, width: bounds.width - 48, height: 64)
        scroll.frame = CGRect(x: 24, y: 78, width: bounds.width - 48, height: max(0, bounds.height - 152))
        var top: CGFloat = 0
        for row in rows {
            row.expanded = row.task == .colors && colorsExpanded
            let height: CGFloat = row.expanded ? 144 : 54
            row.frame = CGRect(x: 0, y: top, width: scroll.contentSize.width, height: height)
            top += height
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(top, scroll.contentSize.height))
    }

    func animateEntrance() {
        guard let layer else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.12
            layer.add(fade, forKey: "checklist.reducedMotion")
        } else {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = bounds.width
            slide.toValue = 0
            slide.duration = 0.800
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "checklist.entrance")
        }
    }

    @objc private func toggleColors(_ sender: Any?) {
        colorsExpanded.toggle()
        needsLayout = true
        rows.first { $0.task == .colors }?.setAccessibilityExpanded(colorsExpanded)
    }

    @objc private func closeSidebar(_ sender: Any?) { onClose?() }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }
}

@MainActor
private final class ChecklistList: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class ChecklistRow: NSButton {
    let task: ChecklistTask
    var completed = false
    var expanded = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { task == .colors }

    init(task: ChecklistTask) {
        self.task = task
        super.init(frame: .zero)
        title = task.label
        isBordered = false
        focusRingType = .none
        isEnabled = task == .colors
        setAccessibilityLabel(task.label)
        setAccessibilityElement(true)
        setAccessibilityRole(task == .colors ? .button : .checkBox)
        if task == .colors { setAccessibilityExpanded(true) }
        if !task.isAvailable { toolTip = "This feature is unavailable in the clone." }
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if expanded {
            NSColor(srgbRed: 40 / 255, green: 43 / 255, blue: 45 / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
        }
        let checkbox = NSBezierPath(roundedRect: CGRect(x: 16, y: 18, width: 18, height: 18), xRadius: 5, yRadius: 5)
        (completed ? NSColor(srgbRed: 245 / 255, green: 248 / 255, blue: 250 / 255, alpha: 1)
            : NSColor(srgbRed: 55 / 255, green: 60 / 255, blue: 62 / 255, alpha: 1)).setFill()
        checkbox.fill()
        if !completed {
            NSColor.white.withAlphaComponent(0.14).setStroke()
            checkbox.lineWidth = 1
            checkbox.stroke()
        }
        let tint = NSColor.white.withAlphaComponent(task.isAvailable || completed || task == .colors ? 0.92 : 0.55)
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: tint]
        if completed { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        NSAttributedString(string: task.label, attributes: attributes).draw(at: CGPoint(x: 48, y: 18))
        let shortcut = NSAttributedString(string: task.shortcut, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white.withAlphaComponent(0.45)
        ])
        shortcut.draw(at: CGPoint(x: bounds.width - 18 - shortcut.size().width, y: 18))
        if expanded {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            let text = NSMutableAttributedString(string: "Stickies and Folders can have color. To set a color, select one or more items, then use the Color option from the Toolbar. Useful for letting things appear separated or connected.", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .paragraphStyle: paragraph
            ])
            let range = (text.string as NSString).range(of: "Color", options: .backwards)
            text.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.92), range: range)
            text.draw(in: CGRect(x: 48, y: 50, width: bounds.width - 72, height: 88))
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

@MainActor
private final class ChecklistCloseButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "Close checklist")
        image?.size = CGSize(width: 20, height: 20)
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor(srgbRed: 55 / 255, green: 60 / 255, blue: 62 / 255, alpha: 1).cgColor
        setAccessibilityLabel("Close checklist")
        identifier = NSUserInterfaceItemIdentifier("Close checklist")
        toolTip = "Close checklist"
    }

    required init?(coder: NSCoder) { nil }
}
