import AppKit

@MainActor
public final class Routes {
    public static let shared = Routes()
    static var pendingStartupURL: URL?

    weak var controller: WindowCoordinator?
    public func route(for url: URL) -> String {
        url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func mountStartup(url: URL) {
        pendingStartupURL = url
    }

    public func mount(controller: WindowCoordinator) {
        self.controller = controller
    }

    public func open(_ url: URL) {
        switch route(for: url) {
        case "authentication":
            NSLog("ray-lite authentication is not available.")
        case "paywall":
            controller?.presentPaywall()
        case "restore":
            Task { await PurchaseAccess.shared.refreshEntitlements() }
        case "code":
            NSLog("ray-lite route code \(url.query ?? "")")
        default:
            NSLog("ray-lite unknown route \(url.absoluteString)")
        }
    }
}

