import Foundation
import OSLog
import WidgetKit

/// Reads Screen Sharing's connections and publishes them to the widget through the App Group.
@MainActor
final class SnapshotWriter {
    private let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "snapshot")
    private let reader = ConnectionStoreReader()

    private var connections: [Connection] = []
    private var groups: [ConnectionGroup] = []
    private var networkNames: [String] = []
    /// False until the Bonjour browser has reported once (avoids flagging everything offline at launch).
    private var networkKnown = false
    private var reachability: [String: Bool] = [:]
    private var lastPublished: Snapshot?
    /// Notified after every publish (menu bar items mirror the widget data).
    var onPublish: (@MainActor (Snapshot) -> Void)?

    private(set) var lastError: String?
    private(set) var readFailure: ReadFailure?
    var connectionCount: Int { connections.count }
    var groupCount: Int { groups.count }
    var networkCount: Int { networkNames.count }

    /// Re-reads Screen Sharing's store, then publishes.
    func refresh(force: Bool = false) {
        guard let iconsURL = AppGroup.iconsURL else {
            lastError = String(localized: "Failed to read recent connections")
            logger.error("App Group container unavailable")
            return
        }

        let contents: ConnectionStoreReader.Contents
        do {
            contents = try reader.read()
            lastError = nil
            readFailure = nil
        } catch {
            let failure: ReadFailure = if case .accessDenied = error { .accessDenied } else { .unreadable }
            if failure != readFailure {
                logger.error("Failed to read Screen Sharing store: \(String(describing: error), privacy: .public)")
            }
            readFailure = failure
            lastError = failure == .accessDenied
                ? String(localized: "No Access to Screen Sharing")
                : String(localized: "Failed to read recent connections")
            // Tell the widget why it's empty instead of leaving it with no snapshot (or a stale one).
            connections = []
            groups = []
            publish(force: force)
            return
        }

        try? FileManager.default.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        connections = contents.connections.map { item in
            var connection = item.connection
            connection.iconFileName = item.coloredModel.flatMap { Self.ensureIcon(forModel: $0, in: iconsURL) }
            return connection
        }
        groups = contents.groups
        publish(force: force)
    }

    /// Updates the Bonjour section without re-reading the store.
    func updateNetwork(_ names: [String]) {
        networkNames = names
        networkKnown = true
        publish()
    }

    /// TCP probe results for non-Bonjour connections, keyed by address.
    func updateReachability(_ results: [String: Bool]) {
        reachability = results
        publish()
    }

    /// Saved connections that are not Bonjour services and need a TCP probe.
    var probeAddresses: [String] {
        connections.filter { $0.bonjourName == nil }.map(\.address)
    }

    /// Called when the host quits: nothing will keep live data fresh, so drop it
    /// rather than showing machines that may have gone away.
    func publishStale() {
        networkNames = []
        networkKnown = false
        reachability = [:]
        publish(force: true)
    }

    // MARK: - Private

    private func publish(force: Bool = false) {
        guard let snapshotURL = AppGroup.snapshotURL else { return }
        let snapshot = Snapshot(
            connections: connections.map(withStatus),
            groups: groups,
            network: networkNames.map(networkConnection(for:)),
            updatedAt: .now,
            readFailure: readFailure
        )
        if !force, let lastPublished,
           lastPublished.connections == snapshot.connections,
           lastPublished.groups == snapshot.groups,
           lastPublished.network == snapshot.network,
           lastPublished.readFailure == snapshot.readFailure {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
            lastPublished = snapshot
            onPublish?(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
            logger.info("Published \(snapshot.connections.count) connections, \(snapshot.groups.count) groups, \(snapshot.network.count) on network")
        } catch {
            lastError = String(localized: "Failed to load recent connections")
            logger.error("Failed to write snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func withStatus(_ connection: Connection) -> Connection {
        var connection = connection
        if let name = connection.bonjourName {
            connection.isOnline = networkKnown
                ? networkNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                : nil
        } else {
            connection.isOnline = reachability[connection.address]
        }
        return connection
    }

    /// A Bonjour service, enriched with the matching saved connection (icon, username) when there is one.
    private func networkConnection(for name: String) -> Connection {
        let host = "\(name)._rfb._tcp.local"
        let saved = connections.first {
            $0.address.removingPercentEncoding?.caseInsensitiveCompare(host) == .orderedSame
        }
        let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? host
        return Connection(
            id: "network:\(name)",
            displayName: name,
            address: encodedHost,
            username: saved?.username,
            url: saved?.url ?? URL(string: "vnc://\(encodedHost)") ?? URL(filePath: "/"),
            model: saved?.model,
            lastConnected: saved?.lastConnected,
            iconFileName: saved?.iconFileName,
            isOnline: true
        )
    }

    private static func ensureIcon(forModel model: String, in iconsURL: URL) -> String? {
        let fileName = DeviceIconRenderer.fileName(forModel: model)
        let fileURL = iconsURL.appending(path: fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) { return fileName }
        guard let png = DeviceIconRenderer.pngData(forModel: model),
              (try? png.write(to: fileURL, options: .atomic)) != nil else { return nil }
        return fileName
    }
}
