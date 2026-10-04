import Foundation

/// A saved Screen Sharing connection, as mirrored into the App Group.
struct Connection: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let address: String
    let username: String?
    let url: URL
    let model: String?
    let lastConnected: Date?
    /// File name of the pre-rendered device icon inside `AppGroup.iconsURL`.
    var iconFileName: String?
    /// `nil` when unknown (host app not running yet, probe pending).
    var isOnline: Bool?

    /// Bonjour name (`Mac mini._rfb._tcp.local`) or plain host / IP, without the VNC port.
    var bonjourName: String? {
        let decoded = address.removingPercentEncoding ?? address
        let suffix = "._rfb._tcp.local"
        return decoded.lowercased().hasSuffix(suffix) ? String(decoded.dropLast(suffix.count)) : nil
    }

    /// Second line of the list layout, e.g. `jane · 192.168.1.20`.
    var subtitle: String {
        let host = bonjourName.map { "\($0).local" } ?? (address.removingPercentEncoding ?? address)
        return [username, host].compactMap { $0 }.joined(separator: " · ")
    }
    /// SF Symbol used when no device icon is available.
    var fallbackSymbol: String {
        guard let model = model?.lowercased() else { return "desktopcomputer" }
        if model.hasPrefix("macmini") { return "macmini" }
        if model.hasPrefix("macbook") { return "laptopcomputer" }
        if model.hasPrefix("macpro") { return "macpro.gen3" }
        if model.hasPrefix("imac") { return "desktopcomputer" }
        return "macmini"
    }
}

/// A user-defined group from Screen Sharing's sidebar.
struct ConnectionGroup: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let memberIDs: [String]
}

struct Snapshot: Codable, Sendable {
    /// All saved connections, in Screen Sharing's order.
    var connections: [Connection]
    var groups: [ConnectionGroup]
    /// Machines currently advertising Screen Sharing over Bonjour (`_rfb._tcp`).
    var network: [Connection]
    var updatedAt: Date
    /// Set when Screen Sharing's connections couldn't be read (connections and groups are then empty).
    var readFailure: ReadFailure?

    static let empty = Snapshot(connections: [], groups: [], network: [], updatedAt: .distantPast)

    func connections(for source: ConnectionSource) -> [Connection]? {
        switch source {
        case .all:
            return connections
        case .network:
            return network
        case .group(let id):
            guard let group = groups.first(where: { $0.id == id }) else { return nil }
            let members = Set(group.memberIDs)
            return connections.filter { members.contains($0.id) }
        }
    }

    func title(for source: ConnectionSource) -> String {
        switch source {
        case .all: ConnectionSource.allTitle
        case .network: ConnectionSource.networkTitle
        case .group(let id): groups.first { $0.id == id }?.name ?? String(localized: "Untitled Group")
        }
    }
}

enum ReadFailure: String, Codable, Sendable {
    /// macOS hasn't allowed access to Screen Sharing's data (prompt pending or denied).
    case accessDenied
    /// The file is missing or its private format changed.
    case unreadable
}

/// What a widget instance displays — mirrors Screen Sharing's sidebar.
enum ConnectionSource: Hashable, Sendable {
    case all
    case network
    case group(String)

    static let allTitle = String(localized: "All Connections")
    static let networkTitle = String(localized: "Network")

    init(identifier: String) {
        switch identifier {
        case "network": self = .network
        case let id where id.hasPrefix("group:"): self = .group(String(id.dropFirst("group:".count)))
        default: self = .all
        }
    }

    var identifier: String {
        switch self {
        case .all: "all"
        case .network: "network"
        case .group(let id): "group:\(id)"
        }
    }

    var symbol: String {
        switch self {
        case .all: "display.2"
        case .network: "network"
        case .group: "rectangle.on.rectangle"
        }
    }
}

enum AppGroup {
    static let identifier = "JMQMP88PPC.fr.axelguilmin.ScreenSharingWidgets"
    static let urlScheme = "screensharingwidgets"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotURL: URL? {
        containerURL?.appending(path: "connections.json")
    }

    static var iconsURL: URL? {
        containerURL?.appending(path: "icons", directoryHint: .isDirectory)
    }

    static func loadSnapshot() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// URL that asks the host app to connect to a saved connection by ID.
    static func connectURL(id: String) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "connect"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url ?? openScreenSharingURL
    }

    /// URL that asks the host app to bring Screen Sharing to the front.
    static let openScreenSharingURL = URL(string: "\(urlScheme)://open-app")!

    /// URL that asks the host app to open the privacy settings needed to read Screen Sharing's data.
    static let grantAccessURL = URL(string: "\(urlScheme)://grant-access")!
}
