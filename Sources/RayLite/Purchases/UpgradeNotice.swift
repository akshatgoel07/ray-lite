import AppKit

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
