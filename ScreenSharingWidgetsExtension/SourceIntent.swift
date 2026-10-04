import AppIntents
import WidgetKit

/// One entry of Screen Sharing's sidebar: All Connections, Network, or a user group.
struct ConnectionSourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Connections"
    static let defaultQuery = ConnectionSourceQuery()

    let id: String
    let name: String

    var source: ConnectionSource { ConnectionSource(identifier: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: source.symbol))
    }

    static let all = ConnectionSourceEntity(id: ConnectionSource.all.identifier, name: ConnectionSource.allTitle)
    static let network = ConnectionSourceEntity(id: ConnectionSource.network.identifier, name: ConnectionSource.networkTitle)
}

struct ConnectionSourceQuery: EntityQuery {
    /// Sections offered in the widget's edit menu, in sidebar order.
    private func available() -> [ConnectionSourceEntity] {
        let groups = AppGroup.loadSnapshot()?.groups ?? []
        return [.all, .network] + groups.map {
            ConnectionSourceEntity(id: ConnectionSource.group($0.id).identifier, name: $0.name)
        }
    }

    func entities(for identifiers: [ConnectionSourceEntity.ID]) async throws -> [ConnectionSourceEntity] {
        let available = available()
        return identifiers.compactMap { id in
            // Keep a deleted group resolvable so the widget can say so instead of silently resetting.
            available.first { $0.id == id } ?? ConnectionSourceEntity(id: id, name: String(localized: "Group Not Found"))
        }
    }

    func suggestedEntities() async throws -> [ConnectionSourceEntity] {
        available()
    }

    func defaultResult() async -> ConnectionSourceEntity? {
        .all
    }
}

enum LayoutStyle: String, AppEnum {
    /// Icons for the small widget, list for medium and larger.
    case automatic
    case grid
    case list

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "View"
    static let caseDisplayRepresentations: [LayoutStyle: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatic", image: .init(systemName: "wand.and.stars")),
        .grid: DisplayRepresentation(title: "Icon View", image: .init(systemName: "square.grid.2x2")),
        .list: DisplayRepresentation(title: "List View", image: .init(systemName: "list.bullet")),
    ]
}

struct SelectSourceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Connections"
    static let description = IntentDescription("Show connections as icons, or in a list")

    @Parameter(title: "Connections")
    var section: ConnectionSourceEntity?

    @Parameter(title: "View", default: .automatic)
    var style: LayoutStyle

    var source: ConnectionSource { section?.source ?? .all }
}
