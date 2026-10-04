import AppIntents
import Foundation

/// Action of the Control Center control.
///
/// `openAppWhenRun` makes the system run `perform()` in the host app's process, which is why
/// this file is compiled into both targets (the extension only needs the declaration).
struct ConnectIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Connection")
    var connectionID: String?

    init() {}

    init(connectionID: String?) {
        self.connectionID = connectionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if HOST_APP
        ScreenSharingLauncher.connect(id: connectionID)
        #endif
        return .result()
    }
}
