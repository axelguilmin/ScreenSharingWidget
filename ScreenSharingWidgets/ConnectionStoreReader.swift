import Foundation

/// Reads the private `connectionsStore` of the macOS 26 Screen Sharing app.
///
/// Layout (undocumented, parsed defensively):
/// - `connectionsStore`: nested binary plist
///   - `connectionDetails[UUID].connectionParameters.<case>._0` → `address`, `displayName`, `username`
///   - `sessionMetadatas[UUID]` → `deviceInfo.model`, `deviceInfo.enclosureColor`, `lastConnectedDate`,
///     `sessionState.restorationAttributes.targetAddress`
/// - `recentConnectionIDs`: nested binary plist, array of UUIDs (most recent first, may contain deleted IDs)
struct ConnectionStoreReader {
    struct RawConnection: Sendable {
        var connection: Connection
        /// Model code with colour suffix, e.g. `Mac17,3@ECOLOR=7`.
        var coloredModel: String?
    }

    struct Contents: Sendable {
        var connections: [RawConnection]
        var groups: [ConnectionGroup]
    }

    enum ReadError: Error {
        /// "Data from other apps" not granted (yet).
        case accessDenied
        case unreadable(Error)
        case malformed
    }

    static let preferencesURL = URL(filePath: NSHomeDirectory())
        .appending(path: "Library/Containers/com.apple.ScreenSharing/Data/Library/Preferences/com.apple.ScreenSharing.plist")

    var preferencesURL: URL = Self.preferencesURL

    func read() throws(ReadError) -> Contents {
        let data: Data
        do { data = try Data(contentsOf: preferencesURL) } catch {
            throw Self.isPermissionError(error) ? .accessDenied : .unreadable(error)
        }
        guard let root = Self.plist(data) as? [String: Any] else { throw .malformed }
        guard let storeData = root["connectionsStore"] as? Data,
              let store = Self.plist(storeData) as? [String: Any] else { return Contents(connections: [], groups: []) }

        let details = store["connectionDetails"] as? [String: Any] ?? [:]
        let metadatas = store["sessionMetadatas"] as? [String: Any] ?? [:]
        let recentIDs = (root["recentConnectionIDs"] as? Data).flatMap { Self.plist($0) as? [String] } ?? []

        let connections: [RawConnection] = details.compactMap { key, value in
            guard let detail = value as? [String: Any] else { return nil }
            return Self.parse(id: key, detail: detail, metadata: metadatas[key] as? [String: Any])
        }

        // Mirror the app's order: recent IDs first, then the rest by last connection date.
        let rank = Dictionary(recentIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = connections.sorted { lhs, rhs in
            switch (rank[lhs.connection.id], rank[rhs.connection.id]) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                let l = lhs.connection.lastConnected ?? .distantPast
                let r = rhs.connection.lastConnected ?? .distantPast
                return l != r ? l > r : lhs.connection.displayName < rhs.connection.displayName
            }
        }

        let groups: [ConnectionGroup] = (store["connectionGroups"] as? [String: Any] ?? [:]).compactMap { key, value in
            guard let group = value as? [String: Any] else { return nil }
            return ConnectionGroup(
                id: group["id"] as? String ?? key,
                name: group["groupName"] as? String ?? String(localized: "Untitled Group"),
                memberIDs: group["members"] as? [String] ?? []
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return Contents(connections: sorted, groups: groups)
    }

    private static func plist(_ data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    private static func parse(id: String, detail: [String: Any], metadata: [String: Any]?) -> RawConnection? {
        // `connectionParameters` is a Swift enum encoded as { "<case>": { "_0": payload } }.
        guard let parameters = detail["connectionParameters"] as? [String: Any],
              let payload = parameters.values
                .compactMap({ ($0 as? [String: Any])?["_0"] as? [String: Any] })
                .first
        else { return nil }

        let address = payload["address"] as? String ?? ""
        let username = (payload["username"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let session = metadata?["sessionState"] as? [String: Any]
        let restoration = session?["restorationAttributes"] as? [String: Any]
        let targetAddress = (restoration?["targetAddress"] as? String).flatMap(URL.init(string:))

        guard let url = makeURL(address: address, username: username) ?? targetAddress else { return nil }

        let name = (payload["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? address.removingPercentEncoding?.replacingOccurrences(of: "._rfb._tcp.local", with: "")
            ?? address

        let deviceInfo = metadata?["deviceInfo"] as? [String: Any]
        let model = deviceInfo?["model"] as? String
        let color = (deviceInfo?["enclosureColor"] as? Int) ?? (deviceInfo?["housingColor"] as? Int)
        let coloredModel = model.map { m in color.map { "\(m)@ECOLOR=\($0)" } ?? m }

        let connection = Connection(
            id: id,
            displayName: name,
            address: address,
            username: username,
            url: url,
            model: model,
            lastConnected: metadata?["lastConnectedDate"] as? Date,
            iconFileName: nil
        )
        return RawConnection(connection: connection, coloredModel: coloredModel)
    }

    /// `address` is stored already percent-encoded for Bonjour names (`Mac%20mini._rfb._tcp.local`).
    private static func makeURL(address: String, username: String?) -> URL? {
        guard !address.isEmpty else { return nil }
        var string = "vnc://"
        if let username, let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) {
            string += "\(encoded)@"
        }
        string += address
        return URL(string: string)
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
        let posix = (error.userInfo[NSUnderlyingErrorKey] as? NSError) ?? error
        return posix.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(posix.code)
    }
}
