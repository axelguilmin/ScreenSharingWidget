import AppKit
import Sparkle

/// Sparkle updates, from the appcast attached to the latest GitHub release (SUFeedURL in Info.plist).
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    /// Set when Sparkle quits the app to install an update and relaunch it.
    private(set) var isRelaunchingForUpdate = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        // Menu bar agent (LSUIElement): bring Sparkle's window to the front.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // No Dock icon: scheduled update alerts are shown without stealing focus.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { isRelaunchingForUpdate = true }
    }
}
