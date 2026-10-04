import AppKit
import OSLog

/// Opens sessions in Screen Sharing on behalf of the widget and the control.
@MainActor
enum ScreenSharingLauncher {
    private static let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "open")

    /// Resolves a saved connection by ID against the latest snapshot; falls back to the app.
    static func connect(id: String?) {
        let url = AppGroup.loadSnapshot()?.connections.first { $0.id == id }?.url
        logger.info("Connect request for \(id ?? "nil", privacy: .public) → \(url?.absoluteString ?? "app", privacy: .public)")
        open(url)
    }

    /// Always targets Screen Sharing explicitly so a `vnc://` URL can never bounce back here.
    static func open(_ url: URL?) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenSharing") else {
            logger.error("Screen Sharing not found")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let url {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }
}
