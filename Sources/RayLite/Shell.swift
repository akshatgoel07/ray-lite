import AppKit
import QuartzCore
import UniformTypeIdentifiers

@MainActor
final class RayLiteApplication: NSApplication {
    weak var verificationWindow: NSWindow?

    override var isActive: Bool { VerificationRuntime.enabled ? verificationWindow?.isKeyWindow == true : super.isActive }
    override var keyWindow: NSWindow? {
        VerificationRuntime.enabled ? (verificationWindow?.isKeyWindow == true ? verificationWindow : nil) : super.keyWindow
    }
    override var mainWindow: NSWindow? { VerificationRuntime.enabled ? verificationWindow : super.mainWindow }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var mainController: MainController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                        .fullSizeContentView],
                            backing: .buffered, defer: false)
        if VerificationRuntime.enabled { window.colorSpace = .sRGB }
        window.title = ""
        window.titleVisibility = .hidden
        window.center()
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        NSApp.appearance = AppPreferences.shared.appearance
        window.contentMinSize = NSSize(width: 520, height: 380)

        let controller = MainController()
        window.contentViewController = controller
        window.delegate = controller
        window.isReleasedWhenClosed = false
        if VerificationRuntime.enabled {
            (NSApp as? RayLiteApplication)?.verificationWindow = window
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderBack(nil)
            window.becomeKey()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        self.window = window
        mainController = controller
        installMenus(controller: controller)
        window.makeFirstResponder(controller.canvasView)

        StoreKitService.shared.start()
        Routes.shared.mount(controller: controller)
        if let pending = Routes.pendingStartupURL {
            Routes.shared.open(pending)
        }
    }

    private func installMenus(controller: MainController) {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "Ray Lite")
        let settings = applicationMenu.addItem(withTitle: "Settings…", action: #selector(MainController.showPreferences(_:)), keyEquivalent: ",")
        settings.target = controller
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide Ray Lite", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = applicationMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Ray Lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File")
        let newNote = fileMenu.addItem(withTitle: "New Note", action: #selector(MainController.createNote(_:)), keyEquivalent: "n")
        newNote.target = controller
        let newSpace = fileMenu.addItem(withTitle: "New Space", action: #selector(MainController.createSpace(_:)), keyEquivalent: "")
        newSpace.target = controller
        let samples = fileMenu.addItem(withTitle: "Add Sample Notes", action: #selector(MainController.addSamples(_:)), keyEquivalent: "")
        samples.target = controller
        let close = fileMenu.addItem(withTitle: "Close Window", action: #selector(MainController.closeWindow(_:)), keyEquivalent: "w")
        close.target = controller
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Delete", #selector(CanvasView.delete(_:)), ""),
            ("Select All", #selector(NSResponder.selectAll(_:)), "a")
        ] {
            let item = editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key == "Z" ? [.command, .shift] : .command
        }
        let viewMenu = NSMenu(title: "View")
        for (title, action, key) in [
            ("Zoom In", #selector(MainController.zoomIn(_:)), "+"),
            ("Zoom Out", #selector(MainController.zoomOut(_:)), "-"),
            ("Actual Size", #selector(MainController.actualSize(_:)), "0"),
            ("Fit Content", #selector(MainController.fitContent(_:)), "9")
        ] {
            let item = viewMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = controller
            if action == #selector(MainController.fitContent(_:)) { item.keyEquivalentModifierMask = [.command, .option] }
        }
        viewMenu.addItem(.separator())
        for number in 1...9 {
            let item = viewMenu.addItem(withTitle: "Space \(number)",
                action: #selector(MainController.switchSpace(_:)), keyEquivalent: String(number))
            item.target = controller
            item.tag = number - 1
        }
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        for submenu in [applicationMenu, fileMenu, editMenu, viewMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainController?.canvasView.finishEditing() == false ? .terminateCancel : .terminateNow
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, !VerificationRuntime.enabled, let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    public func application(_ application: NSApplication,
                            open urls: [URL]) {
        for url in urls where url.scheme == "ray-lite" {
            Routes.shared.open(url)
        }
    }
}

public final class Window: NSWindow {
    public var padding: CGFloat = 12
    private var verificationKey = true

    override public var isKeyWindow: Bool { VerificationRuntime.enabled ? verificationKey : super.isKeyWindow }
    override public var isMainWindow: Bool { VerificationRuntime.enabled ? true : super.isMainWindow }

    override public func resignKey() {
        if VerificationRuntime.enabled { verificationKey = false }
        super.resignKey()
    }

    func layoutTrafficLights() {
        guard let contentView else { return }
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = standardWindowButton(kind) else { continue }
            if button.superview !== contentView {
                button.removeFromSuperview()
                contentView.addSubview(button)
            }
            button.setFrameOrigin(CGPoint(x: 19 + CGFloat(index) * 23, y: contentView.bounds.height - 33))
        }
    }
}

@MainActor
public final class Routes {
    public static let shared = Routes()
    static var pendingStartupURL: URL?

    weak var controller: MainController?
    public func route(for url: URL) -> String {
        url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func mountStartup(url: URL) {
        pendingStartupURL = url
    }

    public func mount(controller: MainController) {
        self.controller = controller
    }

    public func open(_ url: URL) {
        switch route(for: url) {
        case "authentication":
            NSLog("Ray Lite authentication is not available.")
        case "paywall":
            controller?.presentPaywall()
        case "restore":
            Task { await StoreKitService.shared.refreshEntitlements() }
        case "code":
            NSLog("ray-lite route code \(url.query ?? "")")
        default:
            NSLog("ray-lite unknown route \(url.absoluteString)")
        }
    }
}

@MainActor
public final class MainController: NSViewController, NSMenuItemValidation, NSWindowDelegate {
    let canvasView = CanvasView()
    private let settingsButton = CornerCapsule(symbol: "slider.horizontal.3", name: "Board Settings")
    private let counterButton = CornerCapsule(text: "00/10", name: "Checklist")
    private let spaceButton = CornerCapsule(symbol: "antenna.radiowaves.left.and.right", name: "Spaces", showsCaret: true)
    private let plusButton = CornerCapsule(symbol: "plus", name: "Add Content")
    private let contentActionBar = ContentActionBar()
    private var plusMenu: ContentMenuOverlay?
    private var spaceMenu: SpaceMenuOverlay?
    private var boardMenu: BoardSettingsOverlay?
    private var bookmarksSidebar: BookmarksSidebar?
    private var checklistSidebar: ChecklistSidebar?
    private let checklistProgress = ChecklistProgress(defaults: ProcessInfo.processInfo.environment["RAY_LITE_DEFAULTS_SUITE"]
        .flatMap(UserDefaults.init(suiteName:)) ?? .standard)
    private(set) var settingsWindow: NSWindow?
    private let retryButton = CanvasControl(title: "Retry", target: nil, action: nil)
    private let dismissError = CanvasControl(title: "Dismiss", target: nil, action: nil)
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateMessage = NSTextField(wrappingLabelWithString: "")
    private let saveMessage = NSTextField(wrappingLabelWithString: "")
    private let statePanel = NSStackView()
    private let savePanel = NSStackView()

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override public func loadView() {
        view = BoardBackgroundView(frame: NSRect(x: 0, y: 0, width: 1080, height: 720))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 26 / 255, alpha: 1).cgColor
        view.layer?.cornerRadius = 26
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        canvasView.autoresizingMask = [.width, .height]
        canvasView.frame = view.bounds
        view.addSubview(canvasView)

        let capsules = [settingsButton, counterButton, spaceButton, plusButton]
        for (button, width) in zip(capsules, [56.0, 84.0, 82.0, 56.0]) {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        settingsButton.target = self
        settingsButton.action = #selector(toggleBoardSettings(_:))
        counterButton.target = self
        counterButton.action = #selector(toggleChecklist(_:))
        counterButton.title = checklistProgress.counter
        spaceButton.target = self
        spaceButton.action = #selector(toggleSpaceMenu(_:))
        plusButton.target = self
        plusButton.action = #selector(togglePlusMenu(_:))
        view.addSubview(settingsButton)
        let rightControls = NSStackView(views: [counterButton, spaceButton, plusButton])
        rightControls.spacing = 12
        rightControls.alignment = .centerY
        rightControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightControls)
        contentActionBar.translatesAutoresizingMaskIntoConstraints = false
        contentActionBar.isHidden = true
        contentActionBar.downloadButton.target = self
        contentActionBar.downloadButton.action = #selector(downloadSelection(_:))
        contentActionBar.canvas = canvasView
        view.addSubview(contentActionBar)
        plusButton.nextKeyView = canvasView
        canvasView.nextKeyView = plusButton
        retryButton.target = self
        retryButton.action = #selector(retryLoad)
        retryButton.bezelStyle = .rounded
        retryButton.toolTip = "Retry Load"
        retryButton.setAccessibilityLabel("Retry Load")
        retryButton.cell?.setAccessibilityLabel("Retry Load")

        stateTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        stateTitle.textColor = .white
        stateMessage.font = .systemFont(ofSize: 13)
        stateMessage.textColor = NSColor.white.withAlphaComponent(0.65)
        stateMessage.alignment = .center
        stateMessage.maximumNumberOfLines = 6
        stateTitle.alignment = .center
        statePanel.orientation = .vertical
        statePanel.alignment = .centerX
        statePanel.spacing = 12
        for control in [stateTitle, stateMessage, retryButton] { statePanel.addArrangedSubview(control) }
        statePanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statePanel)

        saveMessage.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        saveMessage.textColor = .systemRed
        let warning = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Save error")!)
        warning.contentTintColor = .systemRed
        warning.setContentHuggingPriority(.required, for: .horizontal)
        saveMessage.maximumNumberOfLines = 2
        dismissError.target = canvasView
        dismissError.action = #selector(CanvasView.dismissSaveError(_:))
        dismissError.bezelStyle = .rounded
        dismissError.toolTip = "Dismiss Save Error"
        dismissError.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        dismissError.setContentHuggingPriority(.required, for: .horizontal)
        dismissError.setAccessibilityLabel("Dismiss Save Error")
        dismissError.cell?.setAccessibilityLabel("Dismiss Save Error")
        savePanel.wantsLayer = true
        savePanel.layer?.cornerRadius = 6
        savePanel.layer?.borderWidth = 1
        savePanel.setAccessibilityRole(.group)
        savePanel.setAccessibilityLabel("Save error")
        savePanel.alignment = .centerY
        savePanel.spacing = 8
        savePanel.addArrangedSubview(warning)
        savePanel.addArrangedSubview(saveMessage)
        savePanel.addArrangedSubview(dismissError)
        savePanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savePanel)
        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            settingsButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            rightControls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            rightControls.bottomAnchor.constraint(equalTo: settingsButton.bottomAnchor),
            contentActionBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentActionBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            contentActionBar.heightAnchor.constraint(equalToConstant: 58),
            statePanel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statePanel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 10),
            statePanel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -80),
            stateMessage.widthAnchor.constraint(lessThanOrEqualTo: statePanel.widthAnchor),
            savePanel.leadingAnchor.constraint(equalTo: settingsButton.leadingAnchor),
            savePanel.trailingAnchor.constraint(lessThanOrEqualTo: rightControls.trailingAnchor),
            savePanel.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -12)
        ])
        canvasView.onNotePageChange = { [weak self] visible in
            guard let self else { return }
            let destination: NotePageTransition.Destination = visible ? .page : .board
            for control in [self.settingsButton, rightControls, self.contentActionBar] as [NSView] {
                control.wantsLayer = true
                guard let layer = control.layer else { continue }
                let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                let hidden = CATransform3DMakeTranslation(0, -72, 0)
                let target = visible && !reduced ? hidden : CATransform3DIdentity
                if layer.opacity == (visible ? 0 : 1), CATransform3DEqualToTransform(layer.transform, target) { continue }
                let opacity = NotePageTransition.animation(keyPath: "opacity", to: Float(visible ? 0 : 1), destination: destination)
                opacity.duration = reduced ? 0 : (visible ? 0.18 : 0.467)
                SpringCore.shared.add(opacity, to: layer, key: "rayLite.noteControls")
                let movement = NotePageTransition.animation(keyPath: "transform", to: NSValue(caTransform3D: target), destination: destination)
                movement.duration = opacity.duration
                SpringCore.shared.add(movement, to: layer, key: "rayLite.noteControlsPosition")
            }
            for button in [self.settingsButton, self.spaceButton, self.plusButton] { button.isEnabled = !visible }
        }
        canvasView.onStateChange = { [weak self] in self?.updateCanvasState() }
        canvasView.onNoteCreated = { [weak self] in self?.checklistProgress.complete(.createNote) }
        checklistProgress.onChange = { [weak self] in
            guard let self else { return }
            counterButton.title = checklistProgress.counter
            checklistSidebar?.refresh()
        }
        canvasView.onSelectionChange = { [weak self] in
            guard let self else { return }
            contentActionBar.isNoteSelection = canvasView.notes.filter { self.canvasView.selection.contains($0.id) }
                .allSatisfy { $0.kind == .note }
            contentActionBar.isHidden = canvasView.selection.isEmpty
        }
        AppPreferences.shared.onChange = { [weak self] in self?.applyPreferences() }
        applyPreferences()
        canvasView.loadNotes()
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        (view.window as? Window)?.layoutTrafficLights()
    }

    private func updateCanvasState() {
        switch canvasView.loadState {
        case .empty:
            statePanel.isHidden = false
            stateTitle.stringValue = "Your canvas is empty"
            stateMessage.stringValue = "Choose Note from the plus menu to create a note."
            retryButton.isHidden = true
            plusButton.isEnabled = true
        case .populated:
            statePanel.isHidden = true
            plusButton.isEnabled = true
        case .loadError(let error):
            statePanel.isHidden = false
            stateTitle.stringValue = "Cannot load notes"
            stateMessage.stringValue = error.message
            retryButton.isHidden = false
            plusButton.isEnabled = false
        }
        spaceButton.isEnabled = plusButton.isEnabled
        settingsButton.isEnabled = plusButton.isEnabled
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            savePanel.layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
            savePanel.layer?.borderColor = NSColor.systemRed.cgColor
        }
        saveMessage.stringValue = canvasView.saveError ?? ""
        savePanel.isHidden = canvasView.saveError == nil
        let controls: [NSButton] = [plusButton]
            + (retryButton.isHidden ? [] : [retryButton]) + (savePanel.isHidden ? [] : [dismissError])
        for (control, next) in zip(controls, controls.dropFirst()) { control.nextKeyView = next }
        controls.last?.nextKeyView = canvasView
        canvasView.nextKeyView = plusButton
    }

    @objc func closeWindow(_ sender: Any?) { view.window?.performClose(sender) }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender === view.window ? canvasView.finishEditing() : true
    }

    @objc private func downloadSelection(_ sender: Any?) {
        exportSelectedNotes(sender)
    }

    private func exportSelectedNotes(_ sender: Any?) {
        guard canvasView.finishEditing(), let window = view.window else { return }
        let notes = canvasView.notes.filter { canvasView.selection.contains($0.id) }
        guard !notes.isEmpty else { return }
        if let image = notes.first?.image {
            let panel = NSSavePanel()
            panel.allowedContentTypes = image.contentType.map { [$0] } ?? []
            panel.nameFieldStringValue = image.name
            VerificationRuntime.presentSavePanel(panel, on: window) { url in
                guard let url else { return }
                do { try image.data.write(to: url, options: .atomic) }
                catch { VerificationRuntime.presentSaveError(error, on: window) }
            }
            return
        }
        do {
            for note in notes where note.kind == .note {
                try note.content.exportMarkdown()
            }
        } catch {
            VerificationRuntime.presentSaveError(error, on: window)
        }
    }

    @objc private func togglePlusMenu(_ sender: Any?) {
        if plusMenu != nil {
            closePlusMenu()
            return
        }
        guard canvasView.finishEditing() else { return }
        closeSpaceMenu()
        closeBoardSettings()
        let menu = ContentMenuOverlay(frame: view.bounds)
        menu.autoresizingMask = [.width, .height]
        menu.onClose = { [weak self] in self?.closePlusMenu() }
        menu.onNote = { [weak self] in self?.createNote(nil) }
        menu.onSpace = { [weak self] in self?.createSpace(nil) }
        menu.onBookmarks = { [weak self] in self?.presentBookmarks() }
        view.addSubview(menu)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = view.window?.standardWindowButton(kind), button.superview === view {
                view.addSubview(button, positioned: .above, relativeTo: menu)
            }
        }
        plusMenu = menu
        menu.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(menu)
        menu.animateEntrance()
    }

    private func closePlusMenu() {
        plusMenu?.removeFromSuperview()
        plusMenu = nil
        view.window?.makeFirstResponder(canvasView)
    }

    @objc private func toggleSpaceMenu(_ sender: Any?) {
        if spaceMenu != nil {
            closeSpaceMenu()
            return
        }
        guard canvasView.finishEditing() else { return }
        closePlusMenu()
        closeBoardSettings()
        let menu = SpaceMenuOverlay(frame: view.bounds, spaces: canvasView.spaces,
                                    currentID: canvasView.currentSpaceID)
        menu.autoresizingMask = [.width, .height]
        menu.onClose = { [weak self] in self?.closeSpaceMenu() }
        menu.onSelect = { [weak self] id in
            guard let self else { return }
            closeSpaceMenu()
            canvasView.switchSpace(id)
        }
        view.addSubview(menu)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = view.window?.standardWindowButton(kind), button.superview === view {
                view.addSubview(button, positioned: .above, relativeTo: menu)
            }
        }
        spaceMenu = menu
        menu.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(menu)
        menu.animateEntrance()
    }

    private func closeSpaceMenu() {
        spaceMenu?.removeFromSuperview()
        spaceMenu = nil
        view.window?.makeFirstResponder(canvasView)
    }

    @objc private func toggleBoardSettings(_ sender: Any?) {
        if boardMenu != nil { closeBoardSettings(); return }
        guard canvasView.finishEditing(), let space = canvasView.spaces.first(where: { $0.id == canvasView.currentSpaceID }) else { return }
        closePlusMenu()
        closeSpaceMenu()
        let menu = BoardSettingsOverlay(frame: view.bounds, name: space.name, count: canvasView.notes.count)
        menu.autoresizingMask = [.width, .height]
        menu.onClose = { [weak self] in self?.closeBoardSettings() }
        menu.onRename = { [weak self] name in self?.canvasView.renameCurrentSpace(name) ?? false }
        menu.onDelete = { [weak self] in
            guard let self else { return }
            if canvasView.deleteCurrentSpace() { closeBoardSettings() }
        }
        menu.onPro = { [weak self] in
            self?.closeBoardSettings()
            self?.presentPaywall()
        }
        view.addSubview(menu)
        boardMenu = menu
        (view.window as? Window)?.layoutTrafficLights()
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = view.window?.standardWindowButton(kind) { view.addSubview(button, positioned: .above, relativeTo: menu) }
        }
        menu.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(menu)
    }

    private func closeBoardSettings() {
        boardMenu?.removeFromSuperview()
        boardMenu = nil
        view.window?.makeFirstResponder(canvasView)
    }

    @objc private func toggleChecklist(_ sender: Any?) {
        if checklistSidebar != nil { closeChecklist(); return }
        guard canvasView.finishEditing() else { return }
        closePlusMenu()
        closeSpaceMenu()
        closeBoardSettings()
        let sidebar = ChecklistSidebar(frame: CGRect(x: view.bounds.width - 428, y: 0,
                                                      width: 428, height: view.bounds.height), progress: checklistProgress)
        sidebar.onClose = { [weak self] in self?.closeChecklist() }
        view.addSubview(sidebar)
        if let controls = counterButton.superview, controls !== view { view.addSubview(controls) }
        checklistSidebar = sidebar
        counterButton.state = .on
        counterButton.needsDisplay = true
        sidebar.layoutSubtreeIfNeeded()
        view.window?.makeFirstResponder(sidebar)
        sidebar.animateEntrance()
    }

    private func closeChecklist() {
        checklistSidebar?.removeFromSuperview()
        checklistSidebar = nil
        counterButton.state = .off
        counterButton.needsDisplay = true
        view.window?.makeFirstResponder(counterButton)
    }

    @objc func showPreferences(_ sender: Any?) {
        guard canvasView.finishEditing() else { return }
        closePlusMenu()
        closeSpaceMenu()
        closeBoardSettings()
        if let settingsWindow {
            if !VerificationRuntime.enabled { settingsWindow.makeKeyAndOrderFront(nil) }
            return
        }
        let panel = Window(contentRect: CGRect(x: 0, y: 0, width: 600, height: 466),
                           styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = PreferencesContent(preferences: AppPreferences.shared)
        panel.center()
        panel.layoutTrafficLights()
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        settingsWindow = panel
        if VerificationRuntime.enabled {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.orderBack(nil)
            (NSApp as? RayLiteApplication)?.verificationWindow = panel
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        panel.makeFirstResponder(panel.contentView)
    }

    public func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        settingsWindow = nil
        if VerificationRuntime.enabled { (NSApp as? RayLiteApplication)?.verificationWindow = view.window }
        view.window?.makeFirstResponder(canvasView)
    }

    private func applyPreferences() {
        NSApp.appearance = AppPreferences.shared.appearance
        view.window?.appearance = nil
        (view as? BoardBackgroundView)?.updateFill()
        canvasView.applyPreferences()
    }

    @objc func createSpace(_ sender: Any?) {
        closeBoardSettings()
        closePlusMenu()
        closeSpaceMenu()
        canvasView.newSpace()
    }

    @objc func switchSpace(_ sender: NSMenuItem) {
        closeBoardSettings()
        guard canvasView.spaces.indices.contains(sender.tag) else { return }
        closePlusMenu()
        closeSpaceMenu()
        canvasView.switchSpace(canvasView.spaces[sender.tag].id)
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(closeWindow(_:)) { return view.window != nil }
        if item.action == #selector(switchSpace(_:)) { return canvasView.spaces.indices.contains(item.tag) }
        if item.action == #selector(createSpace(_:)) { return plusButton.isEnabled }
        if item.action == #selector(zoomOut(_:)) { return canvasView.magnification > 0.30001 }
        if item.action == #selector(zoomIn(_:)) { return canvasView.magnification < 3.99999 }
        if item.action == #selector(fitContent(_:)) { return !canvasView.notes.isEmpty }
        if item.action == #selector(addSamples(_:)) || item.action == #selector(createNote(_:)) { return plusButton.isEnabled }
        return true
    }

    @objc func createNote(_ sender: Any?) {
        closeBoardSettings()
        closeSpaceMenu()
        let menu = plusMenu
        plusMenu = nil
        menu?.animateExit()
        view.window?.makeFirstResponder(canvasView)
        canvasView.newNote()
    }

    @objc func zoomIn(_ sender: Any?) { canvasView.zoomIn(sender) }

    @objc func zoomOut(_ sender: Any?) { canvasView.zoomOut(sender) }

    @objc func actualSize(_ sender: Any?) { canvasView.actualSize(sender) }

    @objc func fitContent(_ sender: Any?) { canvasView.fitContent(sender) }

    @objc func addSamples(_ sender: Any?) { canvasView.addSampleNotes() }

    @objc private func retryLoad() { canvasView.loadNotes() }

    public func presentPaywall() {
        let alert = PaywallAlert()
        Task { @MainActor in
            _ = await alert.run(on: view.window)
        }
    }

    private func presentBookmarks() {
        guard bookmarksSidebar == nil, canvasView.finishEditing() else { return }
        closePlusMenu()
        closeSpaceMenu()
        closeBoardSettings()
        let sidebar = BookmarksSidebar(frame: view.bounds)
        sidebar.autoresizingMask = [.width, .height]
        sidebar.onClose = { [weak self] in
            self?.bookmarksSidebar?.removeFromSuperview()
            self?.bookmarksSidebar = nil
            self?.view.window?.makeFirstResponder(self?.canvasView)
        }
        view.addSubview(sidebar)
        bookmarksSidebar = sidebar
        view.window?.makeFirstResponder(sidebar)
        sidebar.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class CanvasControl: NSButton {
    private var pointerInside = false

    override func accessibilityLabel() -> String? { identifier?.rawValue ?? title }

    override var acceptsFirstResponder: Bool { true }

    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    override var isEnabled: Bool {
        didSet { if oldValue != isEnabled { updateOpacity() } }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        updateOpacity()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        updateOpacity()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        guard let layer else { return }
        SpringCore.shared.cancel(layer, keyPath: "opacity", behavior: .keepCurrentValue)
        pointerInside = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        CATransaction.commit()
    }

    private func updateOpacity() {
        guard window != nil, let layer else { return }
        SpringCore.shared.cancel(layer, keyPath: "opacity", behavior: .keepCurrentValue)
        SpringCore.shared.fade(layer, to: pointerInside && isEnabled ? 0.78 : 1,
                               duration: 0.12, key: "rayLite.controlOpacity")
    }
}

@MainActor
private final class ContentActionBar: NSView {
    weak var canvas: CanvasView?
    let downloadButton = ContentActionButton(symbol: "arrow.down.to.line", name: "Download Selected Items")
    private let color = ContentActionButton(symbol: "drop", name: "Color")
    private let folder = ContentActionButton(symbol: "folder", name: "Move to Folder")
    var isNoteSelection = true {
        didSet {
            color.isHidden = isNoteSelection
            folder.frame.origin.x = isNoteSelection ? 81 : 143
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: isNoteSelection ? 144 : 206, height: 58) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        canvas?.hasNotePage == true ? nil : super.hitTest(point)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NotePageTransition.cardColor.cgColor
        layer?.cornerRadius = 29
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: -12)
        self.shadow = shadow
        setAccessibilityRole(.group)
        setAccessibilityLabel("Content actions")
        identifier = NSUserInterfaceItemIdentifier("Content actions")
        color.isEnabled = false
        color.isHidden = true
        folder.isEnabled = false
        for (index, button) in [downloadButton, folder].enumerated() {
            button.frame = CGRect(x: 19 + CGFloat(index) * 62, y: 7, width: 44, height: 44)
            addSubview(button)
        }
        color.frame = CGRect(x: 81, y: 7, width: 44, height: 44)
        addSubview(color)
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class ContentActionButton: NSButton {
    private let symbol: String

    init(symbol: String, name: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        title = ""
        identifier = NSUserInterfaceItemIdentifier(name)
        isBordered = false
        focusRingType = .none
        setAccessibilityLabel(name)
        cell?.setAccessibilityLabel(name)
        toolTip = name
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let tint = NSColor.white.withAlphaComponent(isEnabled ? (isHighlighted ? 0.45 : 0.65) : 0.3)
        drawMenuSymbol(symbol, in: bounds.insetBy(dx: 11, dy: 11), tint: tint)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

@MainActor
private final class CornerCapsule: NSButton {
    private let symbol: String?
    private let showsCaret: Bool

    init(symbol: String? = nil, text: String = "", name: String, showsCaret: Bool = false) {
        self.symbol = symbol
        self.showsCaret = showsCaret
        super.init(frame: .zero)
        title = text
        font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        identifier = NSUserInterfaceItemIdentifier(name)
        isBordered = false
        focusRingType = .none
        setAccessibilityLabel(name)
        cell?.setAccessibilityLabel(name)
        toolTip = name
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 21, yRadius: 21)
        NSColor(srgbRed: 38 / 255, green: 39 / 255, blue: 41 / 255, alpha: 1).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.08).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        if state == .on {
            NSColor(srgbRed: 55 / 255, green: 60 / 255, blue: 62 / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), xRadius: 12, yRadius: 12).fill()
        }
        let tint = NSColor.white.withAlphaComponent(isEnabled ? (isHighlighted ? 0.6 : 0.85) : 0.35)
        if let symbol {
            drawMenuSymbol(symbol, in: CGRect(x: showsCaret ? 17 : (bounds.width - 20) / 2,
                                              y: 11, width: 20, height: 20), tint: tint)
        } else {
            let text = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: tint
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
        if showsCaret {
            drawMenuSymbol("chevron.up", in: CGRect(x: 51, y: 15, width: 12, height: 12), tint: tint)
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 19, yRadius: 19)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

@MainActor
private func drawMenuSymbol(_ name: String, in rect: CGRect, tint: NSColor) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 18, weight: .regular)) else { return }
    let tinted = NSImage(size: image.size, flipped: false) { bounds in
        image.draw(in: bounds)
        tint.setFill()
        bounds.fill(using: .sourceIn)
        return true
    }
    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    tinted.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                          width: size.width, height: size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

@MainActor
private final class ContentMenuOverlay: NSView {
    private let panel = NSView()
    private let importPanel = NSView()
    private var importRow: ContentMenuRow!
    private var hoverExit: DispatchWorkItem?
    var onClose: (() -> Void)?
    var onNote: (() -> Void)?
    var onSpace: (() -> Void)?
    var onBookmarks: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.6).cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Add Content menu")
        for surface in [panel, importPanel] {
            surface.wantsLayer = true
            surface.layer?.cornerRadius = 24
            surface.layer?.borderWidth = 0.5
            surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            surface.layer?.shadowColor = NSColor.black.cgColor
            surface.layer?.shadowOpacity = 0.45
            surface.layer?.shadowRadius = 14
            surface.layer?.shadowOffset = CGSize(width: 0, height: -8)
            addSubview(surface)
        }
        panel.layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
        importPanel.layer?.backgroundColor = NSColor(srgbRed: 46 / 255, green: 50 / 255, blue: 52 / 255, alpha: 1).cgColor
        importPanel.isHidden = true
        let rows: [(String, String, String, CGFloat)] = [
            ("Note", "note.text", "⌘ N", 8),
            ("Sticky", "note", "⇧⌘ N", 53),
            ("Folder", "folder", "", 98),
            ("Webclip", "macwindow", "", 143),
            ("Import", "arrow.down.to.line", "chevron.right", 206),
            ("New Space", "square.3.layers.3d", "arrow.up.right", 270)
        ]
        for (name, symbol, shortcut, top) in rows {
            let row = ContentMenuRow(name: name, symbol: symbol, shortcut: shortcut)
            row.frame = CGRect(x: 8, y: 322 - top - 45, width: 296, height: 45)
            row.isEnabled = name == "Note" || name == "New Space"
            if name == "Note" {
                row.target = self
                row.action = #selector(createNote(_:))
                row.keyEquivalent = "n"
                row.keyEquivalentModifierMask = .command
            }
            if name == "New Space" {
                row.target = self
                row.action = #selector(createSpace(_:))
            }
            row.onHover = { [weak self] inside in
                guard let self else { return }
                if name == "Import", inside {
                    hoverExit?.cancel()
                    importPanel.isHidden = false
                    importRow.showsHover = true
                } else if name == "Import" {
                    importRow.showsHover = true
                    scheduleImportClose()
                } else if inside {
                    hideImport()
                }
            }
            if name == "Import" { importRow = row }
            panel.addSubview(row)
        }
        for top in [196.0, 259.0] {
            let divider = NSView(frame: CGRect(x: 24, y: 322 - top, width: 264, height: 0.5))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            panel.addSubview(divider)
        }
        let bookmarks = ContentMenuRow(name: "Bookmarks from", symbol: "bookmark", shortcut: "Not connected")
        bookmarks.frame = CGRect(x: 8, y: 0, width: 296, height: 60)
        bookmarks.target = self
        bookmarks.action = #selector(openBookmarks(_:))
        bookmarks.onHover = { [weak self] inside in
            if inside { self?.hoverExit?.cancel() } else { self?.scheduleImportClose() }
        }
        importPanel.addSubview(bookmarks)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        panel.frame = CGRect(x: bounds.width - 336, y: 74, width: 312, height: 322)
        importPanel.frame = CGRect(x: panel.frame.minX - 314, y: panel.frame.maxY - 258, width: 312, height: 60)
    }

    func animateEntrance() {
        guard let layer = panel.layer else { return }
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.567
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0, 1, 1]
        opacity.keyTimes = [0, 0.12, 0.45, 1]
        opacity.duration = duration
        layer.add(opacity, forKey: "plus.opacity")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transform = CAKeyframeAnimation(keyPath: "transform")
            let anchor = CGPoint(x: 284, y: -29)
            let pivot = CGPoint(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
            transform.values = [0.12, 0.12, 0.35, 1, 1.015, 1].map { scale in
                CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                    CATransform3DMakeTranslation((anchor.x - pivot.x) * (1 - scale),
                                                                (anchor.y - pivot.y) * (1 - scale), 0))
            }
            transform.keyTimes = [0, 0.12, 0.24, 0.4, 0.6, 1]
            transform.duration = duration
            transform.calculationMode = .cubic
            layer.add(transform, forKey: "plus.transform")
        }
        guard let cover = self.layer else { return }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = NSColor.clear.cgColor
        fade.toValue = cover.backgroundColor
        fade.duration = duration
        cover.add(fade, forKey: "plus.cover")
    }

    func animateExit() {
        hoverExit?.cancel()
        importPanel.isHidden = true
        panel.subviews.compactMap { $0 as? NSControl }.forEach { $0.isEnabled = false }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduced ? 0.12 : 0.467
        if let layer = panel.layer {
            let anchor = CGPoint(x: 284, y: -29)
            let pivot = CGPoint(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
            let scale: CGFloat = 0.02
            let target = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                CATransform3DMakeTranslation((anchor.x - pivot.x) * (1 - scale), (anchor.y - pivot.y) * (1 - scale), 0))
            if !reduced {
                let movement = CABasicAnimation(keyPath: "transform")
                movement.toValue = NSValue(caTransform3D: target)
                movement.duration = 0.2
                movement.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
                SpringCore.shared.add(movement, to: layer, key: "plus.transform")
            }
            SpringCore.shared.fade(layer, to: 0, duration: reduced ? duration : 0.2, key: "plus.opacity")
        }
        if let cover = layer {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.toValue = NSColor.clear.cgColor
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            SpringCore.shared.add(fade, to: cover, key: "plus.cover")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.removeFromSuperview() }
    }

    override func mouseDown(with event: NSEvent) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    @objc private func createNote(_ sender: Any?) { onNote?() }

    @objc private func createSpace(_ sender: Any?) { onSpace?() }

    @objc private func openBookmarks(_ sender: Any?) { onBookmarks?() }

    private func hideImport() {
        hoverExit?.cancel()
        importPanel.isHidden = true
        importRow.showsHover = false
    }

    private func scheduleImportClose() {
        hoverExit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideImport() }
        hoverExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

@MainActor
private final class SpaceMenuOverlay: NSView {
    private let panel = NSView()
    private let spaces: [SpaceRecord]
    var onClose: (() -> Void)?
    var onSelect: ((UUID) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, spaces: [SpaceRecord], currentID: UUID) {
        self.spaces = spaces
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.6).cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Spaces menu")
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
        panel.layer?.cornerRadius = 24
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.45
        panel.layer?.shadowRadius = 14
        panel.layer?.shadowOffset = CGSize(width: 0, height: -8)
        addSubview(panel)
        for (index, space) in spaces.enumerated() {
            let current = space.id == currentID
            let row = ContentMenuRow(name: space.name,
                symbol: current ? "antenna.radiowaves.left.and.right" : "bookmark",
                shortcut: index < 9 ? "⌘ \(index + 1)" : "")
            row.frame = CGRect(x: 8, y: 8 + CGFloat(index) * 45, width: 296, height: 45)
            row.isCurrentSpace = current
            row.setAccessibilityValue(current ? "Current space" : "")
            row.target = self
            row.action = #selector(selectSpace(_:))
            row.tag = index
            panel.addSubview(row)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        panel.frame = CGRect(x: bounds.width - 404, y: 74, width: 312, height: 16 + CGFloat(spaces.count) * 45)
    }

    func animateEntrance() {
        guard let layer = panel.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.35
        layer.add(fade, forKey: "spaces.opacity")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transform = CABasicAnimation(keyPath: "transform")
            let scale: CGFloat = 0.8
            let anchor = CGPoint(x: 271, y: -29)
            let pivot = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            transform.fromValue = NSValue(caTransform3D: CATransform3DConcat(
                CATransform3DMakeScale(scale, scale, 1),
                CATransform3DMakeTranslation((anchor.x - pivot.x) * (1 - scale), (anchor.y - pivot.y) * (1 - scale), 0)))
            transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            transform.duration = fade.duration
            transform.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(transform, forKey: "spaces.transform")
        }
    }

    @objc private func selectSpace(_ sender: NSButton) { onSelect?(spaces[sender.tag].id) }

    override func mouseDown(with event: NSEvent) { onClose?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
}

@MainActor
private final class ContentMenuRow: NSButton {
    private let symbol: String
    private let shortcut: String
    var onHover: ((Bool) -> Void)?
    var isCurrentSpace = false
    var showsHover = false { didSet { needsDisplay = true } }

    init(name: String, symbol: String, shortcut: String) {
        self.symbol = symbol
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = name
        font = .systemFont(ofSize: 14)
        identifier = NSUserInterfaceItemIdentifier(name)
        isBordered = false
        focusRingType = .none
        setAccessibilityLabel(name)
        cell?.setAccessibilityLabel(name)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        super.mouseDown(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        showsHover = isEnabled
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        showsHover = false
        onHover?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsHover || isHighlighted {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 16, yRadius: 16).fill()
        }
        let tint = NSColor.white.withAlphaComponent(isCurrentSpace ? 0.3 : (isEnabled ? 0.95 : 0.38))
        drawMenuSymbol(symbol, in: CGRect(x: 18, y: (bounds.height - 20) / 2, width: 20, height: 20), tint: tint)
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: tint])
        text.draw(at: CGPoint(x: 52, y: (bounds.height - text.size().height) / 2))
        if shortcut == "chevron.right" || shortcut == "arrow.up.right" {
            drawMenuSymbol(shortcut, in: CGRect(x: bounds.width - 30, y: (bounds.height - 14) / 2,
                                               width: 14, height: 14), tint: tint.withAlphaComponent(0.3))
        } else {
            let label = NSAttributedString(string: shortcut, attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white.withAlphaComponent(isCurrentSpace ? 0.2 : (isEnabled ? 0.45 : 0.25))
            ])
            label.draw(at: CGPoint(x: bounds.width - 18 - label.size().width, y: (bounds.height - label.size().height) / 2))
        }
    }
}

@MainActor
private final class BoardSettingsOverlay: NSView, NSTextFieldDelegate {
    private let panel = NSView()
    private let name: String
    private let editRow: ContentMenuRow
    private var nameField: NSTextField?
    private var confirmation: NSView?
    var onClose: (() -> Void)?
    var onRename: ((String) -> Bool)?
    var onDelete: (() -> Void)?
    var onPro: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, name: String, count: Int) {
        self.name = name
        editRow = ContentMenuRow(name: "Edit Space", symbol: "pencil", shortcut: name)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 26 / 255, alpha: 0.6).cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Board settings menu")
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(srgbRed: 33 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1).cgColor
        panel.layer?.cornerRadius = 24
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.45
        panel.layer?.shadowRadius = 14
        panel.layer?.shadowOffset = CGSize(width: 0, height: -8)
        addSubview(panel)
        let delete = ContentMenuRow(name: "Delete Space", symbol: "trash", shortcut: "")
        let pro = ContentMenuRow(name: "Ray Lite Pro", symbol: "square.on.square", shortcut: "\(count) / 20 items")
        for (row, y, action) in [(editRow, 116.0, #selector(editSpace)), (delete, 71.0, #selector(confirmDelete)), (pro, 8.0, #selector(openPro))] {
            row.frame = CGRect(x: 8, y: y, width: 296, height: 45)
            row.target = self
            row.action = action
            panel.addSubview(row)
        }
        let divider = NSView(frame: CGRect(x: 24, y: 62, width: 264, height: 0.5))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        panel.addSubview(divider)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        panel.frame = CGRect(x: 24, y: 74, width: 312, height: 168)
    }

    @objc private func editSpace() {
        guard nameField == nil else { return }
        let field = NSTextField(frame: CGRect(x: 52, y: 125, width: 236, height: 26))
        field.stringValue = name
        field.font = .systemFont(ofSize: 14)
        field.textColor = .white
        field.backgroundColor = NSColor(srgbRed: 51 / 255, green: 54 / 255, blue: 56 / 255, alpha: 1)
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(commitName)
        field.setAccessibilityLabel("Space name")
        editRow.isHidden = true
        panel.addSubview(field)
        nameField = field
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    @objc private func commitName() {
        guard let field = nameField, onRename?(field.stringValue) == true else { return }
        onClose?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            nameField?.removeFromSuperview()
            nameField = nil
            editRow.isHidden = false
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    @objc private func confirmDelete() {
        guard confirmation == nil else { return }
        let content = NSView(frame: panel.bounds)
        content.wantsLayer = true
        content.layer?.backgroundColor = panel.layer?.backgroundColor
        content.layer?.cornerRadius = 24
        let title = NSTextField(labelWithString: "Delete this space and all its notes?")
        title.font = .systemFont(ofSize: 14)
        title.textColor = .white
        title.frame = CGRect(x: 24, y: 112, width: 264, height: 22)
        content.addSubview(title)
        let detail = NSTextField(labelWithString: "Use Undo to restore the space.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = NSColor.white.withAlphaComponent(0.6)
        detail.frame = CGRect(x: 24, y: 84, width: 264, height: 20)
        content.addSubview(detail)
        for (label, x, action) in [("Cancel", 24.0, #selector(cancelDelete)), ("Delete Space", 156.0, #selector(deleteSpace))] {
            let button = NSButton(title: label, target: self, action: action)
            button.identifier = NSUserInterfaceItemIdentifier(label == "Cancel" ? "Cancel Delete Space" : "Confirm Delete Space")
            button.bezelStyle = .rounded
            button.frame = CGRect(x: x, y: 24, width: 132, height: 32)
            content.addSubview(button)
        }
        panel.addSubview(content)
        confirmation = content
    }

    @objc private func cancelDelete() { confirmation?.removeFromSuperview(); confirmation = nil }
    @objc private func deleteSpace() { onDelete?() }
    @objc private func openPro() { onPro?() }
    override func mouseDown(with event: NSEvent) { onClose?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        if confirmation != nil { cancelDelete() } else { onClose?() }
    }
}

@MainActor
private final class BoardBackgroundView: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    func updateFill() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 26 / 255, alpha: 1)
                                  : NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)).cgColor
    }
}

@MainActor
public final class PaywallAlert: NSAlert {
    override public init() {
        super.init()
        messageText = "Ray Lite Pro"
        informativeText = "Purchases are not available in Ray Lite."
        addButton(withTitle: "Close")
    }

    public func run(on window: NSWindow?) async -> NSApplication.ModalResponse {
        if VerificationRuntime.enabled { VerificationRuntime.paywallPresented = true; return .cancel }
        guard let host = window ?? NSApp.mainWindow else { return .cancel }
        return await beginSheetModal(for: host)
    }
}
