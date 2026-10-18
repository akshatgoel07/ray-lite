import AppKit

MainActor.assumeIsolated {
    let app = RayLiteApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(VerificationRuntime.enabled ? .prohibited : .regular)
    let activity = VerificationRuntime.enabled ? ProcessInfo.processInfo.beginActivity(
        options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Native verification") : nil
    defer { if let activity { ProcessInfo.processInfo.endActivity(activity) } }
    let observer = NotificationCenter.default.addObserver(
        forName: NSApplication.didFinishLaunchingNotification, object: app, queue: .main) { _ in
        DispatchQueue.main.async {
            guard let window = delegate.window, let controller = delegate.mainController else { return }
            VerifyDriver.startIfRequested(window: window, canvas: controller.canvasView)
        }
    }
    app.run()
    NotificationCenter.default.removeObserver(observer)
}
