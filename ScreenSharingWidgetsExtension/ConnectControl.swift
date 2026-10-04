import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Entity

/// A saved Screen Sharing connection, selectable in the control's configuration.
struct ConnectionEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Connection"
    static let defaultQuery = ConnectionEntityQuery()

    let id: String
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ connection: Connection) {
        id = connection.id
        name = connection.displayName
        symbol = connection.fallbackSymbol
    }
}

struct ConnectionEntityQuery: EntityQuery {
    private func all() -> [ConnectionEntity] {
        (AppGroup.loadSnapshot()?.connections ?? []).map(ConnectionEntity.init)
    }

    func entities(for identifiers: [ConnectionEntity.ID]) async throws -> [ConnectionEntity] {
        let all = all()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ConnectionEntity] {
        all()
    }

    /// Most recently used connection (snapshot is in Screen Sharing's recent order).
    func defaultResult() async -> ConnectionEntity? {
        all().first
    }
}

// MARK: - Intents

struct SelectConnectionIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Connection"

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?
}

// MARK: - Control

struct ConnectControlValue: Sendable {
    let connectionID: String?
    let name: String
    let symbol: String
    let isOnline: Bool?

    /// Second line of the control (value text): online state.
    var detail: String {
        switch isOnline {
        case true?: String(localized: "Online")
        case false?: String(localized: "Offline")
        case nil: String(localized: "Screen Sharing")
        }
    }
}

struct ConnectControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectConnectionIntent) -> ConnectControlValue {
        value(for: configuration)
    }

    func currentValue(configuration: SelectConnectionIntent) async throws -> ConnectControlValue {
        value(for: configuration)
    }

    private func value(for configuration: SelectConnectionIntent) -> ConnectControlValue {
        guard let entity = configuration.connection else {
            return ConnectControlValue(connectionID: nil, name: String(localized: "Screen Sharing"), symbol: "rectangle.on.rectangle", isOnline: nil)
        }
        let connection = AppGroup.loadSnapshot()?.connections.first { $0.id == entity.id }
        return ConnectControlValue(
            connectionID: entity.id,
            name: connection?.displayName ?? entity.name,
            symbol: connection?.fallbackSymbol ?? entity.symbol,
            isOnline: connection?.isOnline
        )
    }
}

struct ConnectControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "fr.axelguilmin.ScreenSharingWidgets.connect",
            provider: ConnectControlProvider()
        ) { value in
            ControlWidgetButton(action: ConnectIntent(connectionID: value.connectionID)) {
                Label {
                    Text(value.name)
                    Text(value.detail)
                } icon: {
                    Image(systemName: value.symbol)
                }
                .controlWidgetActionHint("Connect to “\(value.name)”")
            }
        }
        .displayName("Screen Sharing")
        .description("Connect to a computer with Screen Sharing.")
        .promptsForUserConfiguration()
    }
}
