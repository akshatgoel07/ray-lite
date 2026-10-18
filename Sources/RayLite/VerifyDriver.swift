import AppKit
import QuartzCore
import CoreText
import ImageIO

@MainActor
enum VerificationRuntime {
    static let enabled = ProcessInfo.processInfo.environment["RAY_LITE_VERIFY_SCRIPT"] != nil
    private static var pendingSave: (NSSavePanel, (URL?) -> Void)?

    static func presentSavePanel(_ panel: NSSavePanel, on window: NSWindow, completion: @escaping (URL?) -> Void) {
        if enabled {
            pendingSave = (panel, completion)
        } else {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    static func completeSavePanel(at url: URL?) -> Bool {
        guard let (_, completion) = pendingSave else { return false }
        pendingSave = nil
        completion(url)
        return true
    }

    private(set) static var saveError: String?

    static func presentSaveError(_ error: Error, on window: NSWindow) {
        if enabled {
            saveError = error.localizedDescription
        } else {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    static var pointerEvents: [NSEvent] = []

    static func nextPointerEvent() -> NSEvent? {
        if enabled { return pointerEvents.isEmpty ? nil : pointerEvents.removeFirst() }
        return NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true)
    }

    static var imagePasteboard: NSPasteboard?

    static var paywallPresented = false

    static var hasSavePanel: Bool { pendingSave != nil }
}

struct VerifyStep: Decodable {
    struct Point: Decodable {
        let x: Double
        let y: Double

        var value: CGPoint { CGPoint(x: x, y: y) }
    }

    struct Region: Decodable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        var value: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    enum Action {
        case dropImages([String], CGPoint)
        case pasteImage(String)
        case resize(CGSize)
        case click(CGPoint)
        case doubleClick(CGPoint)
        case text(String)
        case pasteboard(String)
        case drag(CGPoint, CGPoint, Int)
        case key(String, UInt16)
        case keyEvent(String, UInt16, NSEvent.EventType)
        case pointer(NSEvent.EventType, CGPoint)
        case scroll(Double, Double, NSEvent.Phase, NSEvent.Phase, Bool)
        case pinch(CGPoint, Double, NSEvent.Phase)
        case textControl
        case deactivate
        case appearance(String)
        case menu(String)
        case snapshotWindow(String)
        case savePanel(String?)
        case clickControl(String)
        case focusControl(String)
        case hoverControl(String)
        case pressControl(String, String)
        case detachCanvas
        case checkpoint(String)
        case wait(Int)
        case snapshot(String)
        case dumpState(String)
        case axDump(String)
        case axAction(String, String)
        case record(String, Int, CGRect?)
        case stopRecord
    }

    let kind: String
    let action: Action
    let modifiers: NSEvent.ModifierFlags

    private enum CodingKeys: String, CodingKey {
        case kind, w, h, x, y, from, to, steps, chars, keyCode, dx, dy, phase, momentumPhase, precise
        case magnification, ms, path, paths, modifiers, text, name, fps, region
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var flags: NSEvent.ModifierFlags = []
        for name in try values.decodeIfPresent([String].self, forKey: .modifiers) ?? [] {
            switch name {
            case "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option": flags.insert(.option)
            case "control": flags.insert(.control)
            case "capsLock": flags.insert(.capsLock)
            case "function": flags.insert(.function)
            default:
                throw DecodingError.dataCorruptedError(forKey: .modifiers, in: values,
                                                       debugDescription: "Unknown modifier: \(name)")
            }
        }
        modifiers = flags
        func decodePhase(_ key: CodingKeys) throws -> NSEvent.Phase {
            switch try values.decodeIfPresent(String.self, forKey: key) ?? "none" {
            case "none": return []
            case "began": return .began
            case "changed": return .changed
            case "ended": return .ended
            case "cancelled": return .cancelled
            case "mayBegin": return .mayBegin
            default:
                throw DecodingError.dataCorruptedError(forKey: key, in: values,
                                                       debugDescription: "Unknown gesture phase.")
            }
        }
        kind = try values.decode(String.self, forKey: .kind)
        switch kind {
        case "dropImages":
            action = .dropImages(try values.decode([String].self, forKey: .paths),
                                 CGPoint(x: try values.decode(Double.self, forKey: .x),
                                         y: try values.decode(Double.self, forKey: .y)))
        case "pasteImage": action = .pasteImage(try values.decode(String.self, forKey: .path))
        case "resize":
            let width = try values.decode(Double.self, forKey: .w)
            let height = try values.decode(Double.self, forKey: .h)
            guard width > 0, height > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .w, in: values,
                                                       debugDescription: "Window dimensions must exceed zero.")
            }
            action = .resize(CGSize(width: width, height: height))
        case "click":
            action = .click(CGPoint(x: try values.decode(Double.self, forKey: .x),
                                    y: try values.decode(Double.self, forKey: .y)))
        case "doubleClick":
            action = .doubleClick(CGPoint(x: try values.decode(Double.self, forKey: .x),
                                         y: try values.decode(Double.self, forKey: .y)))
        case "text": action = .text(try values.decode(String.self, forKey: .text))
        case "pasteboard": action = .pasteboard(try values.decode(String.self, forKey: .text))
        case "drag":
            let count = try values.decode(Int.self, forKey: .steps)
            guard (1...10_000).contains(count) else {
                throw DecodingError.dataCorruptedError(forKey: .steps, in: values,
                                                       debugDescription: "Drag steps must be between 1 and 10000.")
            }
            action = .drag(try values.decode(Point.self, forKey: .from).value,
                           try values.decode(Point.self, forKey: .to).value, count)
        case "mouseDown", "mouseDragged", "mouseUp":
            let type: NSEvent.EventType = kind == "mouseDown" ? .leftMouseDown
                : kind == "mouseDragged" ? .leftMouseDragged : .leftMouseUp
            action = .pointer(type, CGPoint(x: try values.decode(Double.self, forKey: .x),
                                           y: try values.decode(Double.self, forKey: .y)))
        case "key", "keyDown", "keyUp":
            let chars = try values.decodeIfPresent(String.self, forKey: .chars)
            let code = try values.decodeIfPresent(UInt16.self, forKey: .keyCode)
            guard chars != nil || code != nil else {
                throw DecodingError.dataCorruptedError(forKey: .chars, in: values,
                                                       debugDescription: "A key needs chars or keyCode.")
            }
            if kind == "key" {
                action = .key(chars ?? "", code ?? 0)
            } else {
                action = .keyEvent(chars ?? "", code ?? 0, kind == "keyDown" ? .keyDown : .keyUp)
            }
        case "scroll":
            action = .scroll(try values.decode(Double.self, forKey: .dx),
                             try values.decode(Double.self, forKey: .dy), try decodePhase(.phase),
                             try decodePhase(.momentumPhase), try values.decodeIfPresent(Bool.self, forKey: .precise) ?? true)
        case "pinch":
            action = .pinch(CGPoint(x: try values.decode(Double.self, forKey: .x),
                                   y: try values.decode(Double.self, forKey: .y)),
                            try values.decode(Double.self, forKey: .magnification), try decodePhase(.phase))
        case "textControl": action = .textControl
        case "deactivate": action = .deactivate
        case "appearance": action = .appearance(try values.decode(String.self, forKey: .name))
        case "menu": action = .menu(try values.decode(String.self, forKey: .name))
        case "snapshotWindow": action = .snapshotWindow(try values.decode(String.self, forKey: .path))
        case "savePanel": action = .savePanel(try values.decodeIfPresent(String.self, forKey: .path))
        case "clickControl": action = .clickControl(try values.decode(String.self, forKey: .name))
        case "focusControl": action = .focusControl(try values.decode(String.self, forKey: .name))
        case "hoverControl": action = .hoverControl(try values.decode(String.self, forKey: .name))
        case "pressControl": action = .pressControl(try values.decode(String.self, forKey: .name), try values.decode(String.self, forKey: .path))
        case "detachCanvas": action = .detachCanvas
        case "checkpoint": action = .checkpoint(try values.decode(String.self, forKey: .path))
        case "wait":
            let milliseconds = try values.decode(Int.self, forKey: .ms)
            guard (0...3_600_000).contains(milliseconds) else {
                throw DecodingError.dataCorruptedError(forKey: .ms, in: values,
                                                       debugDescription: "Wait must be between 0 and 3600000 milliseconds.")
            }
            action = .wait(milliseconds)
        case "snapshot": action = .snapshot(try values.decode(String.self, forKey: .path))
        case "axDump": action = .axDump(try values.decode(String.self, forKey: .path))
        case "axAction":
            let name = try values.decode(String.self, forKey: .name)
            let command = try values.decode(String.self, forKey: .text)
            guard ["press", "pick"].contains(command) else {
                throw DecodingError.dataCorruptedError(forKey: .text, in: values,
                                                       debugDescription: "Use press or pick for an accessibility action.")
            }
            action = .axAction(name, command)
        case "record":
            let fps = try values.decodeIfPresent(Int.self, forKey: .fps) ?? 15
            guard [15, 60].contains(fps) else {
                throw DecodingError.dataCorruptedError(forKey: .fps, in: values, debugDescription: "Use 15 or 60 frames per second.")
            }
            let region = try values.decodeIfPresent(Region.self, forKey: .region)?.value
            if let region, region.width <= 0 || region.height <= 0 {
                throw DecodingError.dataCorruptedError(forKey: .region, in: values, debugDescription: "The frame region must have a positive size.")
            }
            action = .record(try values.decode(String.self, forKey: .path), fps, region)
        case "stopRecord": action = .stopRecord
        case "dumpState": action = .dumpState(try values.decode(String.self, forKey: .path))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values,
                                                   debugDescription: "Unknown verify step: \(kind)")
        }
    }
}

@MainActor
final class VerifyDriver: NSObject {
    static func startIfRequested(window: NSWindow, canvas: CanvasView) {
        guard let path = ProcessInfo.processInfo.environment["RAY_LITE_VERIFY_SCRIPT"] else { return }
        Task { @MainActor in
            do {
                let steps = try JSONDecoder().decode([VerifyStep].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
                let driver = VerifyDriver(window: window, canvas: canvas)
                try await Task.sleep(nanoseconds: 100_000_000)
                try await driver.run(steps)
                NSApp.terminate(nil)
            } catch {
                NSLog("Ray Lite verify failed: \(error)")
                exit(1)
            }
        }
    }

    private let hostWindow: NSWindow
    private var window: NSWindow { (hostWindow.contentViewController as? MainController)?.settingsWindow ?? hostWindow }
    private let canvas: CanvasView
    private var pointer: CGPoint
    private var eventNumber = 0
    private weak var scrollTarget: NSView?
    private weak var hoveredControl: NSButton?
    private var textControl: NSTextField?
    private var pressedSnapshot: (URL, CGPoint)?
    private var pressedSnapshotError: Error?
    private var lastMotionInput: [String: Any] = [:]

    init(window: NSWindow, canvas: CanvasView) {
        self.hostWindow = window
        self.canvas = canvas
        pointer = CGPoint(x: window.contentView?.bounds.midX ?? 0,
                          y: window.contentView?.bounds.midY ?? 0)
        super.init()
    }

    private var recordingTimer: Timer?
    private var recordingFPS = 15
    private var recordingRegion: CGRect?
    private var recordedFrames: [[String: Any]] = []
    private var recordingPath: URL?
    private var recordingError: Error?
    private var recordingWrites: [Task<Void, Error>] = []

    func run(_ steps: [VerifyStep]) async throws {
        var timings: [[String: Any]] = []
        for (index, step) in steps.enumerated() {
            let start = CACurrentMediaTime()
            switch step.action {
            case .dropImages(let paths, let point):
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
                let drop = ImageVerificationDrop(pasteboard: pasteboard, point: canvas.convert(point, to: nil), window: window)
                guard canvas.draggingEntered(drop) == .copy, canvas.performDragOperation(drop) else { throw DriverError.event }
            case .pasteImage(let path):
                let pasteboard = NSPasteboard.withUniqueName()
                defer {
                    VerificationRuntime.imagePasteboard = nil
                    pasteboard.releaseGlobally()
                }
                let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
                let image = ImageAttachment(data: bytes, name: "Image.png")
                let type = NSPasteboard.PasteboardType(image?.contentType?.identifier ?? "public.png")
                pasteboard.setData(bytes, forType: type)
                VerificationRuntime.imagePasteboard = pasteboard
                try sendKey("v", code: 9, type: .keyDown, modifiers: .command)
                try sendKey("v", code: 9, type: .keyUp, modifiers: .command)
            case .resize(let size):
                window.setContentSize(size)
            case .click(let point):
                pointer = point
                sendMouseSequence([(NSEvent.EventType.leftMouseDown, point), (.leftMouseUp, point)],
                                  modifiers: step.modifiers)
            case .doubleClick(let point):
                pointer = point
                sendMouseSequence([(.leftMouseDown, point), (.leftMouseUp, point)],
                                  modifiers: step.modifiers, clickCount: 2)
            case .text(let text):
                for character in text {
                    let chars = String(character)
                    let code: UInt16 = chars == "\n" ? 36 : chars == " " ? 49 : 0
                    try sendKey(chars == "\n" ? "\r" : chars, code: code, type: .keyDown, modifiers: [])
                    try sendKey(chars == "\n" ? "\r" : chars, code: code, type: .keyUp, modifiers: [])
                }
            case .pasteboard(let text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            case .drag(let start, let end, let count):
                var events: [(NSEvent.EventType, CGPoint)] = [(.leftMouseDown, start)]
                for index in 1...count {
                    let fraction = CGFloat(index) / CGFloat(count)
                    events.append((.leftMouseDragged,
                                   CGPoint(x: start.x + (end.x - start.x) * fraction,
                                           y: start.y + (end.y - start.y) * fraction)))
                }
                events.append((.leftMouseUp, end))
                pointer = end
                sendMouseSequence(events, modifiers: step.modifiers)
            case .pointer(let type, let point):
                let before = motionState()
                pointer = point
                sendMouseSequence([(type, point)], modifiers: step.modifiers)
                lastMotionInput = ["before": before, "after": motionState()]
            case .key(let chars, let code):
                try sendKey(chars, code: code, type: .keyDown, modifiers: step.modifiers)
                try sendKey(chars, code: code, type: .keyUp, modifiers: step.modifiers)
            case .keyEvent(let chars, let code, let type):
                try sendKey(chars, code: code, type: type, modifiers: step.modifiers)
            case .scroll(let dx, let dy, let phase, let momentumPhase, let precise):
                let before = motionState()
                guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                             wheelCount: 2, wheel1: Int32(clamping: Int(dy)),
                                             wheel2: Int32(clamping: Int(dx)), wheel3: 0) else {
                    throw DriverError.event
                }
                let screenPoint = window.convertPoint(toScreen: pointer)
                cgEvent.location = CGPoint(x: screenPoint.x,
                                           y: (NSScreen.screens.first?.frame.maxY ?? 0) - screenPoint.y)
                cgEvent.flags = CGEventFlags(rawValue: UInt64(step.modifiers.rawValue))
                cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
                cgEvent.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
                cgEvent.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                                             value: Int64(window.windowNumber))
                guard let source = NSEvent(cgEvent: cgEvent) else { throw DriverError.event }
                let event = VerifyScrollEvent(source: source, window: window, point: pointer,
                                              dx: dx, dy: dy, phase: phase,
                                              momentumPhase: momentumPhase, precise: precise)
                if momentumPhase.isEmpty {
                    if phase.contains(.began) || scrollTarget == nil {
                        scrollTarget = window.contentView?.hitTest(pointer)
                    }
                    window.sendEvent(event)
                } else {
                    guard let scrollTarget else { throw DriverError.event }
                    scrollTarget.scrollWheel(with: event)
                }
                lastMotionInput = ["before": before, "after": motionState()]
            case .pinch(let point, let magnification, let phase):
                let before = motionState()
                pointer = point
                canvas.handleMagnify(at: canvas.convert(point, from: nil),
                                     magnification: magnification, phase: phase)
                lastMotionInput = ["before": before, "after": motionState()]
            case .textControl:
                guard let view = canvas.itemViews.first(where: { canvas.selection.contains($0.id) }) else {
                    throw DriverError.event
                }
                let field = NSTextField(frame: CGRect(x: 16, y: 16, width: 160, height: 64))
                field.stringValue = "Editable note"
                view.addSubview(field)
                textControl = field
            case .appearance(let name):
                window.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
                canvas.itemViews.forEach { $0.applyColor() }
                canvas.updateSelectionOverlay()
            case .menu(let name):
                func invoke(in menu: NSMenu) -> Bool {
                    for (index, item) in menu.items.enumerated() {
                        if item.title == name {
                            let target = item.target
                            if target == nil, let action = item.action {
                                var responder = window.firstResponder
                                while let current = responder {
                                    if current.responds(to: action) { item.target = current; break }
                                    responder = current.nextResponder
                                }
                            }
                            defer { item.target = target }
                            menu.update()
                            menu.performActionForItem(at: index)
                            return true
                        }
                        if let submenu = item.submenu, invoke(in: submenu) { return true }
                    }
                    return false
                }
                guard let menu = NSApp.mainMenu, invoke(in: menu) else { throw DriverError.event }
            case .snapshotWindow(let path):
                guard let frame = window.contentView?.superview,
                      let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw DriverError.snapshot }
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw DriverError.snapshot }
                try write(data, to: URL(fileURLWithPath: path))
            case .savePanel(let path):
                guard VerificationRuntime.completeSavePanel(at: path.map { URL(fileURLWithPath: $0) }) else {
                    throw DriverError.event
                }
            case .clickControl(let name):
                let button = try control(named: name)
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                pointer = point
                sendMouseSequence([(.leftMouseDown, point), (.leftMouseUp, point)], modifiers: step.modifiers)
            case .focusControl(let name):
                guard window.makeFirstResponder(try control(named: name)) else { throw DriverError.event }
            case .hoverControl(let name):
                let button = try control(named: name)
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                guard let event = NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { throw DriverError.event }
                if let previous = hoveredControl,
                   let exit = NSEvent.enterExitEvent(with: .mouseExited, location: point, modifierFlags: [],
                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                       context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                    previous.mouseExited(with: exit)
                }
                button.mouseEntered(with: event)
                hoveredControl = button
            case .pressControl(let name, let path):
                let button = try control(named: name)
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                pressedSnapshot = (URL(fileURLWithPath: path), point)
                pressedSnapshotError = nil
                let timer = Timer(timeInterval: 0.08, target: self, selector: #selector(capturePressedControl), userInfo: nil, repeats: false)
                RunLoop.main.add(timer, forMode: .common)
                guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw DriverError.event }
                window.sendEvent(down)
                if let pressedSnapshotError { throw pressedSnapshotError }
            case .deactivate:
                window.resignKey()
            case .detachCanvas:
                canvas.removeFromSuperview()
            case .checkpoint(let path):
                let url = URL(fileURLWithPath: path)
                try snapshot(to: url.appendingPathExtension("png"))
                try dumpState(to: url.appendingPathExtension("json"))
            case .wait(let milliseconds):
                try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            case .snapshot(let path):
                let frame = try snapshotImage()
                let url = URL(fileURLWithPath: path)
                try await Task.detached(priority: .utility) { try Self.writePNG(frame, to: url) }.value
            case .axDump(let path):
                try write(JSONSerialization.data(withJSONObject: accessibilityTree(window), options: [.prettyPrinted, .sortedKeys]),
                          to: URL(fileURLWithPath: path))
            case .axAction(let name, let action):
                guard let element = canvas.accessibilityChildren()?.compactMap({ $0 as? NoteAccessibilityElement })
                    .first(where: { $0.accessibilityLabel() == name }) else { throw DriverError.event }
                let result = action == "press" ? element.accessibilityPerformPress() : element.accessibilityPerformPick()
                guard result else { throw DriverError.event }
            case .record(let path, let fps, let region):
                guard recordingTimer == nil else { throw DriverError.event }
                recordingWrites = []
                recordingFPS = fps
                recordingRegion = region
                recordingPath = URL(fileURLWithPath: path)
                recordedFrames = []
                recordingError = nil
                captureRecordingFrame()
                let timer = Timer(timeInterval: 1 / Double(fps), target: self, selector: #selector(captureRecordingFrame), userInfo: nil, repeats: true)
                timer.tolerance = 0
                recordingTimer = timer
                RunLoop.main.add(timer, forMode: .common)
                RunLoop.main.add(timer, forMode: .eventTracking)
            case .stopRecord:
                recordingTimer?.invalidate()
                recordingTimer = nil
                for task in recordingWrites { try await task.value }
                recordingWrites = []
                if let recordingError { throw recordingError }
                if let recordingPath {
                    try write(JSONSerialization.data(withJSONObject: recordedFrames, options: [.prettyPrinted, .sortedKeys]),
                              to: recordingPath.appendingPathComponent("frames.json"))
                }
                recordingPath = nil
            case .dumpState(let path):
                try dumpState(to: URL(fileURLWithPath: path))
            }
            if recordingFPS == 60 {
                switch step.action {
                case .key, .keyEvent, .text, .click, .doubleClick, .clickControl, .drag:
                    captureRecordingFrame()
                default: break
                }
            }
            timings.append(["index": index, "kind": step.kind, "timestamp": start, "completed": CACurrentMediaTime(), "milliseconds": (CACurrentMediaTime() - start) * 1000])
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        if let path = ProcessInfo.processInfo.environment["RAY_LITE_VERIFY_SCRIPT"] {
            try write(JSONSerialization.data(withJSONObject: timings, options: [.prettyPrinted, .sortedKeys]),
                      to: URL(fileURLWithPath: path).appendingPathExtension("timings.json"))
        }
    }

    @objc private func captureRecordingFrame() {
        guard let recordingPath else { return }
        let path = recordingPath.appendingPathComponent(String(format: "%05d.png", recordedFrames.count))
        do {
            let time = CACurrentMediaTime()
            let frame = try snapshotImage(region: recordingRegion)
            let captured = CACurrentMediaTime()
            recordingWrites.append(Task.detached(priority: .utility) {
                try Self.writePNG(frame, to: path)
            })
            func animations(in layer: CALayer?) -> [[String: Any]] {
                guard let layer else { return [] }
                let active: [[String: Any]] = (layer.animationKeys() ?? []).compactMap { key in
                    guard let animation = layer.animation(forKey: key) else { return nil }
                    return ["key": key, "duration": animation.duration, "beginTime": animation.beginTime,
                            "keyPath": (animation as? CAPropertyAnimation)?.keyPath ?? ""]
                }
                return active + (layer.sublayers ?? []).flatMap { animations(in: $0) }
            }
            recordedFrames.append(["path": path.path, "timestamp": time, "captured": captured,
                                   "animations": animations(in: window.contentView?.layer)])
        } catch {
            recordingError = error
        }
    }

    private func accessibilityTree(_ value: Any, depth: Int = 0) -> [String: Any] {
        guard depth < 30, let element = value as? NSAccessibilityProtocol else { return [:] }
        var result: [String: Any] = [
            "role": element.accessibilityRole()?.rawValue ?? "",
            "label": element.accessibilityLabel() ?? element.accessibilityTitle() ?? element.accessibilityRoleDescription() ?? "",
            "identifier": element.accessibilityIdentifier() ?? "",
            "subrole": element.accessibilitySubrole()?.rawValue ?? "",
            "value": String(describing: element.accessibilityValue() ?? ""),
            "selected": element.isAccessibilitySelected(),
            "focused": element.isAccessibilityFocused(),
            "enabled": element.isAccessibilityEnabled(),
            "frame": rectangle(element.accessibilityFrame())
        ]
        result["actions"] = value is NoteAccessibilityElement ? ["AXPress", "AXPick"]
            : element.accessibilityRole() == .button && element.isAccessibilityEnabled() ? ["AXPress"] : []
        result["children"] = (element.accessibilityChildren() ?? []).map { accessibilityTree($0, depth: depth + 1) }
        return result
    }

    @objc private func capturePressedControl() {
        guard let (url, point) = pressedSnapshot else { return }
        do { try snapshot(to: url) } catch { pressedSnapshotError = error }
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0) { NSApp.postEvent(up, atStart: false) }
        pressedSnapshot = nil
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func control(named name: String) throws -> NSButton {
        guard let content = window.contentView,
              let button = descendants(of: content).compactMap({ $0 as? NSButton })
                .first(where: { $0.identifier?.rawValue == name || $0.title == name }) else { throw DriverError.event }
        return button
    }

    private func sendKey(_ chars: String, code: UInt16, type: NSEvent.EventType,
                         modifiers: NSEvent.ModifierFlags) throws {
        let characters = modifiers.contains(.shift) ? chars.uppercased() : chars
        guard let event = NSEvent.keyEvent(with: type, location: pointer, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code) else { throw DriverError.event }
        guard window.firstResponder != nil else { throw DriverError.event }
        if type == .keyDown, modifiers.contains(.command), let menu = NSApp.mainMenu {
            if performMenuKey(event, menu: menu) { return }
        }
        if VerificationRuntime.enabled {
            if type == .keyDown { window.firstResponder?.keyDown(with: event) }
            else { window.firstResponder?.keyUp(with: event) }
        } else {
            window.sendEvent(event)
        }
    }

    private func performMenuKey(_ event: NSEvent, menu: NSMenu) -> Bool {
        if !VerificationRuntime.enabled, NSApp.keyWindow === window { return menu.performKeyEquivalent(with: event) }
        var targets: [(NSMenuItem, AnyObject?)] = []
        func scopeTargets(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { scopeTargets(submenu) }
                guard item.target == nil, let action = item.action else { continue }
                var responder = window.firstResponder
                while let current = responder {
                    if current.responds(to: action) {
                        targets.append((item, item.target))
                        item.target = current
                        break
                    }
                    responder = current.nextResponder
                }
            }
        }
        scopeTargets(menu)
        defer { for (item, target) in targets { item.target = target } }
        return menu.performKeyEquivalent(with: event)
    }

    private func sendMouseSequence(_ events: [(NSEvent.EventType, CGPoint)],
                                   modifiers: NSEvent.ModifierFlags, clickCount: Int = 1) {
        let mouseEvents = events.compactMap { type, point -> NSEvent? in
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime + Double(eventNumber) / 1000,
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)
        }
        guard let first = mouseEvents.first else { return }
        let target = window.contentView?.hitTest(first.locationInWindow)
        if events.count > 2, !(target is NSControl), !(target is NSTextView) {
            for event in mouseEvents { window.sendEvent(event) }
            return
        }
        if VerificationRuntime.enabled, target is NoteBlockControl {
            VerificationRuntime.pointerEvents = Array(mouseEvents.dropFirst())
            defer { VerificationRuntime.pointerEvents = [] }
            target?.mouseDown(with: first)
            return
        }
        for event in mouseEvents.dropFirst() { NSApp.postEvent(event, atStart: false) }
        if VerificationRuntime.enabled, let text = target as? NoteTextView, first.type == .leftMouseDown {
            text.mouseDown(with: first)
        } else {
            window.sendEvent(first)
        }
        while let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                          until: Date(), inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
    }

    nonisolated private static func writePNG(_ frame: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw DriverError.snapshot
        }
        CGImageDestinationAddImage(destination, frame, nil)
        guard CGImageDestinationFinalize(destination) else { throw DriverError.snapshot }
    }

    private func snapshot(to url: URL) throws {
        try Self.writePNG(snapshotImage(), to: url)
    }

    private func snapshotImage(region: CGRect? = nil) throws -> CGImage {
        guard let content = window.contentView else { throw DriverError.snapshot }
        content.layoutSubtreeIfNeeded()
        window.appearance?.performAsCurrentDrawingAppearance { content.displayIfNeeded() }
        guard let layer = content.layer else { throw DriverError.snapshot }
        func displayLayers(_ layer: CALayer) {
            layer.displayIfNeeded()
            for child in layer.sublayers ?? [] { displayLayers(child) }
        }
        displayLayers(layer)
        let frame = region ?? content.bounds
        guard content.bounds.contains(frame) else { throw DriverError.snapshot }
        let scale = window.backingScaleFactor
        guard let context = CGContext(data: nil, width: Int(frame.width * scale),
            height: Int(frame.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw DriverError.snapshot
        }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        func hasAnimations(_ layer: CALayer) -> Bool {
            !(layer.animationKeys() ?? []).isEmpty || (layer.sublayers ?? []).contains(where: hasAnimations)
        }
        let renderedLayer = hasAnimations(layer) ? (layer.presentation() ?? layer) : layer
        renderedLayer.render(in: context)
        guard let image = context.makeImage() else { throw DriverError.snapshot }
        return image
    }

    private func motionState() -> [String: Any] {
        let viewport = canvas.viewport
        return ["scale": viewport.scale,
                "translation": ["x": viewport.translation.x, "y": viewport.translation.y],
                "cameraAnimating": canvas.isCameraAnimating,
                "notes": canvas.itemViews.map { view in
                    ["id": view.id.uuidString, "frame": rectangle(view.frame),
                     "opacity": view.layer?.presentation()?.opacity ?? view.layer?.opacity ?? 1]
                }]
    }

    private func dumpState(to url: URL) throws {
        func animations(in layer: CALayer?) -> [String] {
            guard let layer else { return [] }
            return (layer.animationKeys() ?? []) + (layer.sublayers ?? []).flatMap { animations(in: $0) }
        }
        func animationLayers(in layer: CALayer?) -> [[String: Any]] {
            guard let layer else { return [] }
            let keys = layer.animationKeys() ?? []
            let current: [[String: Any]] = keys.isEmpty && layer.name?.hasPrefix("Note page") != true ? [] : [
                ["layer": String(describing: type(of: layer)), "name": layer.name ?? "", "keys": keys,
                 "frame": rectangle(layer.frame), "bounds": rectangle(layer.bounds),
                 "flipped": layer.isGeometryFlipped,
                 "scale": layer.value(forKeyPath: "transform.scale") as? Double ?? 1,
                 "presentationScale": layer.presentation()?.value(forKeyPath: "transform.scale") as? Double ?? 1,
                 "properties": keys.compactMap { (layer.animation(forKey: $0) as? CAPropertyAnimation)?.keyPath },
                 "values": keys.compactMap { key -> [String: Any]? in
                     guard let animation = layer.animation(forKey: key) as? CABasicAnimation,
                           let keyPath = animation.keyPath else { return nil }
                     return ["keyPath": keyPath, "from": String(describing: animation.fromValue),
                             "to": String(describing: animation.toValue), "duration": animation.duration,
                             "presentation": String(describing: layer.presentation()?.value(forKeyPath: keyPath))]
                 }]
            ]
            return current + (layer.sublayers ?? []).flatMap { animationLayers(in: $0) }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let notes: [[String: Any]] = canvas.notes.map { note in
            let view = canvas.itemViews.first { $0.id == note.id }
            let textLayer = view?.contentLayer.sublayers?.first?.sublayers?.first as? CATextLayer
            let attributed = textLayer?.string as? NSAttributedString ?? NSAttributedString(string: "")
            let textLayers = view?.contentLayer.sublayers?.first?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
            let visible = textLayers.reduce(note.text.contains("\n") ? 1 : 0) { count, layer in
                let text = layer.string as? NSAttributedString ?? NSAttributedString(string: "")
                let framesetter = CTFramesetterCreateWithAttributedString(text)
                let path = CGPath(rect: layer.bounds, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
                return count + CTFrameGetVisibleStringRange(frame).length
            }
            return ["id": note.id.uuidString, "text": note.text, "order": note.order,
                    "kind": note.kind.rawValue, "imageBytes": note.image?.data.count ?? 0,
                    "thumbnailWidth": view?.thumbnailSize.width ?? 0,
                    "thumbnailHeight": view?.thumbnailSize.height ?? 0,
                    "borderWidth": view?.container.borderWidth ?? 0,
                    "frame": rectangle(note.frame), "displayFrame": rectangle(view?.frame ?? .zero),
                    "viewFrame": rectangle(canvas.viewRect(fromCanvas: note.frame)),
                    "textFrame": rectangle(view?.contentLayer.sublayers?.first?.frame ?? .zero),
                    "cornerRadius": view?.container.cornerRadius ?? 0,
                    "opacity": view?.layer?.presentation()?.opacity ?? view?.layer?.opacity ?? 1,
                    "modelOpacity": view?.layer?.opacity ?? 1,
                    "animations": animations(in: view?.layer),
                    "fontName": (attributed.length > 0 ? (attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName : nil) ?? "",
                    "previewCharacters": attributed.length, "previewVisibleCharacters": visible]
        }
        let loadState: String
        switch canvas.loadState {
        case .empty: loadState = "empty"
        case .populated: loadState = "populated"
        case .loadError: loadState = "loadError"
        }
        let origin = canvas.viewPoint(from: .zero)
        let point = canvas.convert(pointer, from: nil)
        let actionBar = window.contentView.flatMap { content in
            descendants(of: content).first { $0.identifier?.rawValue == "Content actions" }
        }
        let canvasPoint = canvas.canvasPoint(from: point)
        let buttons = window.contentView.map { descendants(of: $0).compactMap { view -> [String: Any]? in
            guard let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor else { return nil }
            return ["name": button.identifier?.rawValue ?? button.title, "title": button.title,
                    "enabled": button.isEnabled, "focused": window.firstResponder === button,
                    "fontSize": button.font?.pointSize ?? 0,
                    "opacity": button.layer?.presentation()?.opacity ?? button.layer?.opacity ?? 1,
                    "animations": animations(in: button.layer),
                    "tooltip": button.toolTip ?? "", "frame": rectangle(button.convert(button.bounds, to: nil))]
        } } ?? []
        func menuState(_ menu: NSMenu) -> [[String: Any]] {
            return menu.items.filter { !$0.isSeparatorItem }.map { item in
                var enabled = item.isEnabled
                if let action = item.action {
                    var target = NSApp.target(forAction: action, to: item.target, from: item)
                    if target == nil, item.target == nil {
                        var responder = window.firstResponder
                        while let current = responder {
                            if current.responds(to: action) { target = current; break }
                            responder = current.nextResponder
                        }
                    }
                    if let validator = target as? NSMenuItemValidation { enabled = validator.validateMenuItem(item) }
                    else if let validator = target as? NSUserInterfaceValidations { enabled = validator.validateUserInterfaceItem(item) }
                    else { enabled = target != nil }
                }
                return ["title": item.title, "enabled": enabled, "key": item.keyEquivalent,
                        "children": item.submenu.map { menuState($0) } ?? []]
            }
        }
        let editor = canvas.subviews.compactMap { $0 as? NoteEditor }.first
        var textBounds = CGRect.zero
        if let editor, let container = editor.textView.textContainer, let layout = editor.textView.layoutManager {
            layout.ensureLayout(for: container)
            textBounds = layout.usedRect(for: container)
        }
        var editorContent: [String: Any] = [:]
        var editorRuns: [[String: Any]] = []
        if let editor {
            editorContent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(editor.content)) as? [String: Any] ?? [:]
            editor.textView.textStorage?.enumerateAttributes(in: NSRange(location: 0, length: editor.textView.string.utf16.count)) { attributes, range, _ in
                let font = attributes[.font] as? NSFont
                editorRuns.append(["location": range.location, "length": range.length,
                    "font": font?.fontName ?? "", "size": font?.pointSize ?? 0,
                    "underline": attributes[.underlineStyle] as? Int ?? 0,
                    "strike": attributes[.strikethroughStyle] as? Int ?? 0,
                    "link": String(describing: attributes[.link] ?? "")])
            }
        }
        var outlineElements: [[String: Any]] = []
        canvas.overlayLayer.path?.applyWithBlock { pointer in
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            outlineElements.append(["type": element.type.rawValue,
                "points": (0..<count).map { ["x": element.points[$0].x, "y": element.points[$0].y] }])
        }
        let editorState: [String: Any] = ["frame": rectangle(editor?.frame ?? .zero),
                       "textFrame": rectangle(editor?.textView.frame ?? .zero),
                       "visibleText": rectangle(editor?.textView.visibleRect ?? .zero),
                       "usedText": rectangle(textBounds),
                       "backControl": rectangle(editor?.backControl.frame ?? .zero),
                       "destination": editor.map { String(describing: $0.destination) } ?? "board",
                       "scrollOffset": editor?.scrollView.contentView.bounds.minY ?? 0,
                       "selectionLocation": editor?.textView.selectedRange().location ?? 0,
                       "selectionLength": editor?.textView.selectedRange().length ?? 0,
                       "pointerInText": editor.map { ["x": $0.textView.convert(pointer, from: nil).x, "y": $0.textView.convert(pointer, from: nil).y] } ?? [:],
                       "hitView": window.contentView?.hitTest(pointer).map { String(describing: type(of: $0)) } ?? "",
                       "subviews": editor?.subviews.map { ["view": String(describing: type(of: $0)), "hidden": $0.isHidden] } ?? [],
                       "columnWidth": editor?.textView.textContainer?.containerSize.width ?? 0,
                       "headingFontSize": editor?.textView.textStorage.flatMap { storage in
                           storage.length > 0 ? (storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize : nil
                       } ?? 0,
                       "bodyFontSize": editor.flatMap { editor in
                           let index = NotePageTypography.headingRange(in: editor.textView.string).length
                           guard let storage = editor.textView.textStorage, index < storage.length else { return nil as CGFloat? }
                           return (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize
                       } ?? 0]
        let state: [String: Any] = [
            "preferences": ["cornerStyle": AppPreferences.shared.cornerStyle.rawValue,
                "noteFont": AppPreferences.shared.noteFont.rawValue, "appearance": AppPreferences.shared.theme.rawValue],
            "paywallPresented": VerificationRuntime.paywallPresented,
            "state": loadState,
            "currentSpaceID": canvas.currentSpaceID.uuidString,
            "spaces": canvas.spaces.map { ["id": $0.id.uuidString, "name": $0.name, "order": $0.order] },
            "focus": window.firstResponder.map { String(describing: type(of: $0)) } ?? "",
            "focusedNote": (window.firstResponder as? CanvasItemView)?.id.uuidString ?? "",
            "displayPreferences": ["reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency],
            "buttons": buttons,
            "labels": window.contentView.map { descendants(of: $0).compactMap { view -> [String: Any]? in
                guard let label = view as? NSTextField, !label.isHiddenOrHasHiddenAncestor else { return nil }
                return ["text": label.stringValue, "fontSize": label.font?.pointSize ?? 0,
                        "frame": rectangle(label.convert(label.bounds, to: nil))]
            } } ?? [],
            "menus": NSApp.mainMenu.map { menuState($0) } ?? [],
            "editor": editorState,
            "editorContent": editorContent,
            "editorRuns": editorRuns,
            "outlineElements": outlineElements,
            "outline": rectangle(canvas.overlayLayer.path?.boundingBoxOfPath ?? .zero),
            "outlineWidth": canvas.overlayLayer.lineWidth,
            "outlineColor": canvas.overlayLayer.strokeColor?.components ?? [],
            "outlineSublayers": (canvas.overlayLayer.sublayers ?? []).compactMap { ($0 as? CAShapeLayer)?.path }
                .map { rectangle($0.boundingBoxOfPath) },
            "contentActionBar": ["visible": actionBar?.isHidden == false,
                "frame": rectangle(actionBar?.frame ?? .zero),
                "radius": actionBar?.layer?.cornerRadius ?? 0,
                "shadowRadius": actionBar?.shadow?.shadowBlurRadius ?? 0],
            "savePanelVisible": VerificationRuntime.hasSavePanel || window.attachedSheet is NSSavePanel,
            "notes": notes,
            "saveError": canvas.saveError ?? "",
            "selection": canvas.selection.map(\.uuidString).sorted(),
            "gesture": canvas.dragger.gesture.state.name,
            "textControl": ["value": textControl?.stringValue ?? "",
                            "editorText": (window.firstResponder as? NSTextView)?.string ?? "",
                            "hasTextFocus": window.firstResponder is NSTextView],
            "undo": ["canUndo": window.undoManager?.canUndo ?? false,
                     "canRedo": window.undoManager?.canRedo ?? false],
            "handles": canvas.resizeHandles.map { ["corner": $0.0.rawValue, "frame": rectangle($0.1)] },
            "viewport": ["scale": canvas.magnification, "translation": ["x": origin.x, "y": origin.y],
                         "bounds": rectangle(canvas.bounds), "pinching": canvas.isPinching,
                         "cameraAnimating": canvas.isCameraAnimating, "cameraTimer": canvas.hasCameraTimer,
                         "targetScale": canvas.cameraTarget.scale,
                         "targetTranslation": ["x": canvas.cameraTarget.translation.x, "y": canvas.cameraTarget.translation.y]],
            "lastMotionInput": lastMotionInput,
            "canvasAttached": canvas.window != nil,
            "layerAnimations": animations(in: canvas.layer),
            "animationLayers": animationLayers(in: canvas.layer),
            "timestamp": CACurrentMediaTime(),
            "pointer": ["x": point.x, "y": point.y, "canvasX": canvasPoint.x, "canvasY": canvasPoint.y,
                        "hitNoteID": canvas.noteID(atView: point)?.uuidString ?? ""],
            "controls": window.contentView?.subviews.compactMap { view -> [String: Any]? in
                guard let stack = view as? NSStackView, !stack.isHidden else { return nil }
                return ["frame": rectangle(stack.frame), "children": stack.arrangedSubviews.map { rectangle($0.frame) }]
            } ?? [],
            "window": ["title": window.title, "w": window.contentView?.bounds.width ?? 0, "h": window.contentView?.bounds.height ?? 0,
                       "headless": VerificationRuntime.enabled, "alpha": window.alphaValue,
                       "processActive": NSRunningApplication.current.isActive,
                       "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
                       "processPID": ProcessInfo.processInfo.processIdentifier,
                       "ignoresMouseEvents": window.ignoresMouseEvents,
                       "savePanelPending": VerificationRuntime.hasSavePanel,
                       "savePanelError": VerificationRuntime.saveError ?? "",
                       "isKey": window.isKeyWindow, "isActive": NSApp.isActive,
                       "isVisible": window.isVisible, "isMain": window.isMainWindow,
                       "hasAppKeyWindow": NSApp.keyWindow != nil, "hasAppMainWindow": NSApp.mainWindow != nil,
                       "canBecomeKey": window.canBecomeKey,
                       "activationPolicy": NSApp.activationPolicy().rawValue]
        ]
        try write(JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]), to: url)
    }

    private func rectangle(_ rect: CGRect) -> [String: CGFloat] {
        let rect = rect.isNull || rect.isInfinite ? CGRect.zero : rect
        return ["x": rect.minX, "y": rect.minY, "w": rect.width, "h": rect.height]
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private enum DriverError: Error {
        case event, snapshot
    }
}

@MainActor
private final class VerifyScrollEvent: NSEvent {
    private let source: NSEvent
    private let targetWindow: NSWindow
    private let point: CGPoint
    private let horizontalDelta: CGFloat
    private let verticalDelta: CGFloat
    private let scrollPhase: NSEvent.Phase
    private let nativeMomentumPhase: NSEvent.Phase
    private let precise: Bool

    init(source: NSEvent, window: NSWindow, point: CGPoint, dx: Double, dy: Double,
         phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, precise: Bool) {
        self.source = source
        targetWindow = window
        self.point = point
        horizontalDelta = dx
        verticalDelta = dy
        scrollPhase = phase
        nativeMomentumPhase = momentumPhase
        self.precise = precise
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var type: NSEvent.EventType { .scrollWheel }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { targetWindow.windowNumber }
    override var locationInWindow: NSPoint { point }
    override var timestamp: TimeInterval { source.timestamp }
    override var modifierFlags: NSEvent.ModifierFlags { source.modifierFlags }
    override var scrollingDeltaX: CGFloat { horizontalDelta }
    override var scrollingDeltaY: CGFloat { verticalDelta }
    override var deltaX: CGFloat { source.deltaX }
    override var deltaY: CGFloat { source.deltaY }
    override var deltaZ: CGFloat { source.deltaZ }
    override var phase: NSEvent.Phase { scrollPhase }
    override var momentumPhase: NSEvent.Phase { nativeMomentumPhase }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var isDirectionInvertedFromDevice: Bool { source.isDirectionInvertedFromDevice }
    override var cgEvent: CGEvent? { source.cgEvent }
}
