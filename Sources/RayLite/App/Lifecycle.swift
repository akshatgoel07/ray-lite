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
    var windowCoordinator: WindowCoordinator?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable,
                                        .fullSizeContentView],
                            backing: .buffered, defer: false)
        if VerificationRuntime.enabled { window.colorSpace = .sRGB }
        window.title = "ray-lite"
        window.titleVisibility = .hidden
        window.center()
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        NSApp.appearance = AppPreferences.shared.appearance
        window.contentMinSize = NSSize(width: 520, height: 380)

        let controller = WindowCoordinator()
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
        windowCoordinator = controller
        installMenus(controller: controller)
        window.makeFirstResponder(controller.boardSurface)

        PurchaseAccess.shared.start()
        Routes.shared.mount(controller: controller)
        if let pending = Routes.pendingStartupURL {
            Routes.shared.open(pending)
        }
    }

    private func installMenus(controller: WindowCoordinator) {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "ray-lite")
        let settings = applicationMenu.addItem(withTitle: "Settings…", action: #selector(WindowCoordinator.showPreferences(_:)), keyEquivalent: ",")
        settings.target = controller
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide ray-lite", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = applicationMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit ray-lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileMenu = NSMenu(title: "File")
        let newNote = fileMenu.addItem(withTitle: "New Note", action: #selector(WindowCoordinator.createNote(_:)), keyEquivalent: "n")
        newNote.target = controller
        let newSpace = fileMenu.addItem(withTitle: "New Space", action: #selector(WindowCoordinator.createSpace(_:)), keyEquivalent: "")
        newSpace.target = controller
        let samples = fileMenu.addItem(withTitle: "Add Sample Notes", action: #selector(WindowCoordinator.addSamples(_:)), keyEquivalent: "")
        samples.target = controller
        let close = fileMenu.addItem(withTitle: "Close Window", action: #selector(WindowCoordinator.closeWindow(_:)), keyEquivalent: "w")
        close.target = controller
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Delete", #selector(BoardSurface.delete(_:)), ""),
            ("Select All", #selector(NSResponder.selectAll(_:)), "a")
        ] {
            let item = editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key == "Z" ? [.command, .shift] : .command
        }
        let viewMenu = NSMenu(title: "View")
        for (title, action, key) in [
            ("Zoom In", #selector(WindowCoordinator.zoomIn(_:)), "+"),
            ("Zoom Out", #selector(WindowCoordinator.zoomOut(_:)), "-"),
            ("Actual Size", #selector(WindowCoordinator.actualSize(_:)), "0"),
            ("Fit Content", #selector(WindowCoordinator.fitContent(_:)), "9")
        ] {
            let item = viewMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = controller
            if action == #selector(WindowCoordinator.fitContent(_:)) { item.keyEquivalentModifierMask = [.command, .option] }
        }
        viewMenu.addItem(.separator())
        for number in 1...9 {
            let item = viewMenu.addItem(withTitle: "Space \(number)",
                action: #selector(WindowCoordinator.switchSpace(_:)), keyEquivalent: String(number))
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
        windowCoordinator?.boardSurface.finishEditing() == false ? .terminateCancel : .terminateNow
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

