import AppKit

@MainActor
final class AppPreferences {
    enum CornerStyle: String, CaseIterable { case sharp = "Sharp corners", round = "Round corners" }
    enum NoteFont: String, CaseIterable { case mixed = "Mono/Sans", mono = "Mono", sans = "Sans" }
    enum Theme: String, CaseIterable { case auto = "Auto", dark = "Dark", light = "Light" }

    static let shared = AppPreferences(defaults: ProcessInfo.processInfo.environment["RAY_LITE_DEFAULTS_SUITE"]
        .flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    private let defaults: UserDefaults
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var cornerStyle: CornerStyle {
        get { CornerStyle(rawValue: defaults.string(forKey: "cornerStyle") ?? "") ?? .sharp }
        set { defaults.set(newValue.rawValue, forKey: "cornerStyle"); onChange?() }
    }

    var noteFont: NoteFont {
        get { NoteFont(rawValue: defaults.string(forKey: "noteFont") ?? "") ?? .mixed }
        set { defaults.set(newValue.rawValue, forKey: "noteFont"); onChange?() }
    }

    var theme: Theme {
        get { Theme(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "appearance"); onChange?() }
    }

    var appearance: NSAppearance? {
        switch theme {
        case .auto: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    func font(size: CGFloat, heading: Bool = false) -> NSFont {
        switch noteFont {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .sans: return .systemFont(ofSize: size)
        case .mixed: return heading ? .systemFont(ofSize: size) : .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

@MainActor
final class PreferencesContent: NSView {
    private var choices: NSView?
    private let preferences: AppPreferences

    override var acceptsFirstResponder: Bool { true }

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(frame: CGRect(x: 0, y: 0, width: 600, height: 466))
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 29 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1).cgColor
        layer?.cornerRadius = 26
        layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Settings")
        addLabel("Settings", frame: CGRect(x: 160, y: 17, width: 280, height: 25), size: 18, centered: true, dim: true)
        for (index, name) in ["Open Scratch Pad with", "Display images and videos with", "Font for stickies", "Color theme"].enumerated() {
            addLabel(name, frame: CGRect(x: 22, y: 69 + CGFloat(index) * 50, width: 310, height: 24), size: 16)
        }
        for (text, frame) in [("-", CGRect(x: 324, y: 66, width: 70, height: 30)),
                              ("⌥", CGRect(x: 406, y: 66, width: 70, height: 30)),
                              ("Space", CGRect(x: 488, y: 66, width: 92, height: 30))] {
            let control = PreferenceControl(title: text, identifier: "Hotkey \(text)")
            control.frame = frame
            control.isEnabled = false
            control.setAccessibilityValue("Option Space, unavailable")
            addSubview(control)
        }
        addChoice("Corner style", title: preferences.cornerStyle.rawValue, x: 438, y: 116, width: 142,
                  values: AppPreferences.CornerStyle.allCases.map(\.rawValue)) { [weak self] value in
            guard let style = AppPreferences.CornerStyle(rawValue: value) else { return }
            self?.preferences.cornerStyle = style
        }
        addChoice("Note font", title: preferences.noteFont.rawValue, x: 457, y: 166, width: 123,
                  values: AppPreferences.NoteFont.allCases.map(\.rawValue)) { [weak self] value in
            guard let font = AppPreferences.NoteFont(rawValue: value) else { return }
            self?.preferences.noteFont = font
        }
        addChoice("Appearance", title: preferences.theme.rawValue, x: 472, y: 216, width: 108,
                  values: AppPreferences.Theme.allCases.map(\.rawValue)) { [weak self] value in
            guard let theme = AppPreferences.Theme(rawValue: value) else { return }
            self?.preferences.theme = theme
        }
        let footer = NSTextField(wrappingLabelWithString: "Ray Lite \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
        footer.frame = CGRect(x: 88, y: 378, width: 424, height: 58)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        footer.attributedStringValue = NSAttributedString(string: footer.stringValue, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.42), .kern: 1, .paragraphStyle: paragraph
        ])
        footer.alignment = .center
        addSubview(footer)
        for child in subviews { child.setFrameOrigin(CGPoint(x: child.frame.minX, y: bounds.height - child.frame.maxY)) }
    }

    required init?(coder: NSCoder) { nil }

    private func addLabel(_ text: String, frame: CGRect, size: CGFloat, centered: Bool = false, dim: Bool = false) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size)
        label.textColor = NSColor.white.withAlphaComponent(dim ? 0.5 : 0.95)
        label.alignment = centered ? .center : .left
        addSubview(label)
    }

    private func addChoice(_ name: String, title: String, x: CGFloat, y: CGFloat, width: CGFloat,
                           values: [String], onSelect: @escaping (String) -> Void) {
        let button = PreferenceControl(title: title, identifier: name)
        button.symbol = name == "Appearance" ? "face.smiling" : nil
        button.frame = CGRect(x: x, y: y, width: width, height: 30)
        button.onPress = { [weak self, weak button] in
            guard let self, let button else { return }
            if choices != nil { closeChoices(); return }
            let height = CGFloat(values.count) * 30 + 8
            let list = NSView(frame: CGRect(x: x, y: bounds.height - y - 34 - height, width: width, height: height))
            list.wantsLayer = true
            list.layer?.backgroundColor = NSColor(srgbRed: 51 / 255, green: 54 / 255, blue: 56 / 255, alpha: 1).cgColor
            list.layer?.cornerRadius = 12
            for (index, value) in values.enumerated() {
                let option = PreferenceControl(title: value, identifier: "\(name): \(value)")
                option.showsCaret = false
                option.frame = CGRect(x: 0, y: height - CGFloat(index + 1) * 30 - 4, width: width, height: 30)
                option.onPress = { [weak self, weak button] in
                    button?.title = value
                    button?.setAccessibilityValue(value)
                    button?.needsDisplay = true
                    self?.closeChoices()
                    onSelect(value)
                }
                list.addSubview(option)
            }
            addSubview(list)
            choices = list
        }
        addSubview(button)
    }

    private func closeChoices() {
        choices?.removeFromSuperview()
        choices = nil
    }

    override func mouseDown(with event: NSEvent) { closeChoices() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        if choices != nil { closeChoices() } else { window?.performClose(sender) }
    }
}

@MainActor
private final class PreferenceControl: NSButton {
    var onPress: (() -> Void)?
    var showsCaret = true
    var symbol: String?

    init(title: String, identifier: String) {
        super.init(frame: .zero)
        self.title = title
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        isBordered = false
        font = .systemFont(ofSize: 15)
        target = self
        action = #selector(press)
        setAccessibilityLabel(identifier)
        setAccessibilityValue(title)
    }

    required init?(coder: NSCoder) { nil }
    @objc private func press() { onPress?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 51 / 255, green: 54 / 255, blue: 56 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let text = NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white.withAlphaComponent(0.95)])
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            tinted.draw(in: CGRect(x: 14, y: 7, width: 16, height: 16))
        }
        text.draw(at: CGPoint(x: symbol == nil ? 14 : 40, y: (bounds.height - text.size().height) / 2))
        if showsCaret {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.width - 24, y: 13))
            path.line(to: CGPoint(x: bounds.width - 19, y: 18))
            path.line(to: CGPoint(x: bounds.width - 14, y: 13))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(0.28).setStroke()
            path.stroke()
        }
    }
}
