import AppKit
import OSLog
import ServiceManagement
import SwiftUI

@main
struct ScreenSharingWidgetsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    // Menu bar UI is AppKit (StatusBarController): tooltips and a variable number of
    // pinned items aren't possible with SwiftUI's MenuBarExtra.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
@Observable
final class HostModel {
    let writer = SnapshotWriter()
    private var watcher: PlistWatcher?
    private var browser: NetworkBrowser?
    private var prober: ReachabilityProber?
    private var timer: Timer?

    private static let userDisabledLoginItemKey = "userDisabledLoginItem"
    @ObservationIgnored private let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "app")

    var status = "…"
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    func start() {
        refresh(force: true)
        watcher = PlistWatcher(url: ConnectionStoreReader.preferencesURL) { [weak self] in
            self?.refresh()
        }
        watcher?.start()
        browser = NetworkBrowser { [weak self] names in
            self?.writer.updateNetwork(names)
            self?.updateStatus()
        }
        browser?.start()
        prober = ReachabilityProber { [weak self] results in
            self?.writer.updateReachability(results)
        }
        prober?.start()
        prober?.setAddresses(writer.probeAddresses)
        // Safety net in case a file event is missed.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The widget is useless without this process: make sure it comes back after a reboot.
        // `.notFound` happens after the bundle is replaced, so re-register on anything but `.enabled`,
        // unless the user explicitly turned it off from the menu.
        let status = SMAppService.mainApp.status
        logger.notice("Login item status at launch: \(String(describing: status), privacy: .public)")
        if status != .enabled && !UserDefaults.standard.bool(forKey: Self.userDisabledLoginItemKey) {
            setLaunchAtLogin(true, userInitiated: false)
        }
    }

    func refresh(force: Bool = false) {
        writer.refresh(force: force)
        prober?.setAddresses(writer.probeAddresses)
        updateStatus()
    }

    private func updateStatus() {
        status = writer.lastError
            ?? [
                String(localized: "\(writer.connectionCount) connections"),
                String(localized: "\(writer.groupCount) groups"),
                String(localized: "\(writer.networkCount) on the network"),
            ].joined(separator: " · ")
    }

    func setLaunchAtLogin(_ enabled: Bool, userInitiated: Bool = true) {
        if userInitiated {
            UserDefaults.standard.set(!enabled, forKey: Self.userDisabledLoginItemKey)
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        let status = SMAppService.mainApp.status
        logger.notice("Login item status: \(String(describing: status), privacy: .public)")
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = status == .enabled
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = HostModel()
    private let updater = Updater()
    private var statusBar: StatusBarController?
    private let welcome = WelcomeWindowController()
    private let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "open")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background data provider for the widget: never let AppKit reap it.
        ProcessInfo.processInfo.disableAutomaticTermination("Feeds the Screen Sharing widget")
        ProcessInfo.processInfo.disableSuddenTermination()
        let statusBar = StatusBarController(model: model, updater: updater) { [weak self] in self?.welcome.show() }
        self.statusBar = statusBar
        model.writer.onPublish = { [weak statusBar] snapshot in statusBar?.update(with: snapshot) }
        model.start()
        welcome.showIfFirstLaunch()
    }

    /// Diagnostics: who asked us to quit (Apple Event sender, or the app's own menu).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value {
            let name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?"
            logger.notice("Quit requested by pid \(pid, privacy: .public) (\(name, privacy: .public))")
        } else {
            logger.notice("Quit requested from within the app")
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("Terminating, publishing stale snapshot")
        model.writer.publishStale()
    }

    /// Widget taps are delivered to the containing app: `vnc://` links from cells,
    /// `screensharingwidgets://` for app-level actions.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            logger.info("Open request: \(url.absoluteString, privacy: .public)")
            switch url.scheme {
            case "vnc":
                ScreenSharingLauncher.open(url)
            case AppGroup.urlScheme where url.host() == "open-app":
                ScreenSharingLauncher.open(nil)
            case AppGroup.urlScheme where url.host() == "connect":
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "id" }?.value
                ScreenSharingLauncher.connect(id: id)
            default:
                break
            }
        }
    }

}
