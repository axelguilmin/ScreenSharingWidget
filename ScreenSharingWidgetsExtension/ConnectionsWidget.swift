import AppKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ConnectionsEntry: TimelineEntry {
    let date: Date
    let title: String
    let source: ConnectionSource
    /// `nil` when the configured group no longer exists.
    let connections: [Connection]?
    var style: LayoutStyle = .automatic
    var readFailure: ReadFailure?
    let isPlaceholder: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConnectionsEntry {
        ConnectionsEntry(date: .now, title: ConnectionSource.allTitle, source: .all,
                         connections: Connection.samples, isPlaceholder: true)
    }

    func snapshot(for configuration: SelectSourceIntent, in context: Context) async -> ConnectionsEntry {
        let entry = makeEntry(for: configuration)
        // Widget gallery: show something meaningful before the host app has ever run.
        if context.isPreview, entry.connections?.isEmpty ?? true {
            return ConnectionsEntry(date: .now, title: entry.title, source: entry.source,
                                    connections: Connection.samples, style: entry.style, isPlaceholder: false)
        }
        return entry
    }

    func timeline(for configuration: SelectSourceIntent, in context: Context) async -> Timeline<ConnectionsEntry> {
        // The host app calls reloadAllTimelines() whenever Screen Sharing's store or the network changes.
        Timeline(entries: [makeEntry(for: configuration)], policy: .never)
    }

    private func makeEntry(for configuration: SelectSourceIntent) -> ConnectionsEntry {
        let snapshot = AppGroup.loadSnapshot() ?? .empty
        let source = configuration.source
        return ConnectionsEntry(
            date: .now,
            title: snapshot.title(for: source),
            source: source,
            connections: snapshot.connections(for: source),
            style: configuration.style,
            readFailure: snapshot.readFailure,
            isPlaceholder: false
        )
    }
}

// MARK: - Widget

struct ConnectionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "fr.axelguilmin.ScreenSharingWidgets.connections", intent: SelectSourceIntent.self, provider: Provider()) { entry in
            ConnectionsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Screen Sharing")
        .description("Your Screen Sharing connections, one click away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct ScreenSharingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ConnectionsWidget()
        ConnectControl()
    }
}

// MARK: - Views

struct ConnectionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ConnectionsEntry

    private var layout: (columns: Int, rows: Int) {
        switch family {
        case .systemSmall: (2, 2)
        case .systemMedium: (4, 1)
        case .systemLarge: (4, 3)
        case .systemExtraLarge: (8, 3)
        default: (4, 1)
        }
    }

    private var iconSize: CGFloat {
        switch family {
        case .systemSmall: 40
        case .systemMedium: 56
        default: 52
        }
    }

    private var resolvedStyle: LayoutStyle {
        guard entry.style == .automatic else { return entry.style }
        return family == .systemSmall ? .grid : .list
    }

    private var showsTitle: Bool {
        family == .systemLarge || family == .systemExtraLarge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                Label(entry.title, systemImage: entry.source.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.bottom, 4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let connections = entry.connections, !connections.isEmpty {
            switch resolvedStyle {
            case .grid, .automatic: connectionGrid(connections)
            case .list: ConnectionList(connections: connections, family: family)
                    .redacted(reason: entry.isPlaceholder ? .placeholder : [])
            }
        } else {
            EmptyStateView(source: entry.source, groupExists: entry.connections != nil,
                           readFailure: entry.source == .network ? nil : entry.readFailure)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func connectionGrid(_ connections: [Connection]) -> some View {
        let capacity = layout.columns * layout.rows
        let overflow = connections.count > capacity
        let visible = Array(connections.prefix(overflow ? capacity - 1 : capacity))
        let hidden = connections.count - visible.count
        // Fixed slots, filled from the top-left like Screen Sharing's icon view.
        let rows = layout.rows

        Grid(horizontalSpacing: 4, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let index = row * layout.columns + column
                        Group {
                            if index < visible.count {
                                ConnectionCell(connection: visible[index], iconSize: iconSize, compact: family == .systemSmall)
                            } else if overflow && index == visible.count {
                                OverflowCell(count: hidden, iconSize: iconSize, compact: family == .systemSmall)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

struct ConnectionCell: View {
    let connection: Connection
    let iconSize: CGFloat
    let compact: Bool

    var body: some View {
        ConnectionLink(connection: connection) {
            VStack(spacing: compact ? 4 : 6) {
                DeviceIcon(connection: connection)
                    .frame(width: iconSize, height: iconSize * 0.75, alignment: .bottom)
                    .offlineDimmed(connection.isOnline == false)
                Text(connection.displayName)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(connection.isOnline == false ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .accessibilityLabel(connection.isOnline == false
            ? Text("Connect to “\(connection.displayName)”, offline")
            : Text("Connect to “\(connection.displayName)”"))
    }
}

/// Connects on click, except for the sample machines shown before real data is available
/// (placeholder, gallery): their addresses are made up.
struct ConnectionLink<Content: View>: View {
    let connection: Connection
    @ViewBuilder let content: Content

    var body: some View {
        if connection.isSample {
            content
        } else {
            Link(destination: connection.url) { content }
        }
    }
}

extension View {
    /// Offline machines: greyed-out icon, like an unavailable item.
    func offlineDimmed(_ offline: Bool) -> some View {
        saturation(offline ? 0 : 1).opacity(offline ? 0.4 : 1)
    }
}

/// List presentation, like Screen Sharing's list view: icon, name, user · host, status.
struct ConnectionList: View {
    let connections: [Connection]
    let family: WidgetFamily

    private var columns: Int { family == .systemExtraLarge ? 2 : 1 }
    private var rowsPerColumn: Int {
        switch family {
        case .systemSmall, .systemMedium: 3
        default: 6
        }
    }
    private var showsSubtitle: Bool { family != .systemSmall }

    var body: some View {
        let capacity = columns * rowsPerColumn
        let visible = Array(connections.prefix(capacity))
        HStack(alignment: .top, spacing: 16) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 0) {
                    ForEach(0..<rowsPerColumn, id: \.self) { row in
                        let index = column * rowsPerColumn + row
                        Group {
                            if index < visible.count {
                                ConnectionRow(connection: visible[index], showsSubtitle: showsSubtitle)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxHeight: .infinity)
                        if row < rowsPerColumn - 1 && index + 1 < visible.count {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ConnectionRow: View {
    let connection: Connection
    let showsSubtitle: Bool

    var body: some View {
        ConnectionLink(connection: connection) {
            HStack(spacing: 10) {
                DeviceIcon(connection: connection)
                    .frame(width: 32, height: 24)
                    .offlineDimmed(connection.isOnline == false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(connection.isOnline == false ? .secondary : .primary)
                    if showsSubtitle {
                        Text(connection.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                StatusDot(isOnline: connection.isOnline)
            }
            .contentShape(.rect)
        }
    }
}

struct StatusDot: View {
    let isOnline: Bool?

    var body: some View {
        if let isOnline {
            Circle()
                .fill(isOnline ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
                .accessibilityLabel(isOnline ? Text("Online") : Text("Offline"))
        }
    }
}

struct DeviceIcon: View {
    let connection: Connection

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
        } else {
            Image(systemName: connection.fallbackSymbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }

    private func loadImage() -> NSImage? {
        guard let name = connection.iconFileName,
              let url = AppGroup.iconsURL?.appending(path: name) else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct OverflowCell: View {
    let count: Int
    let iconSize: CGFloat
    let compact: Bool

    var body: some View {
        Link(destination: AppGroup.openScreenSharingURL) {
            VStack(spacing: compact ? 4 : 6) {
                Text(verbatim: "+\(count)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: iconSize, height: iconSize)
                Text("All")
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
    }
}

struct EmptyStateView: View {
    let source: ConnectionSource
    let groupExists: Bool
    /// Network results don't depend on Screen Sharing's data, so it's `nil` there.
    var readFailure: ReadFailure?

    private var message: (title: String, detail: String) {
        switch source {
        case _ where readFailure == .accessDenied:
            (String(localized: "No Access to Screen Sharing"), String(localized: "Click to turn on Screen Sharing Widgets in Privacy & Security › Full Disk Access."))
        case _ where readFailure == .unreadable:
            (String(localized: "Failed to read recent connections"), String(localized: "Check for an update of Screen Sharing Widgets."))
        case _ where !groupExists:
            (String(localized: "Group Not Found"), String(localized: "This group was deleted in Screen Sharing. Edit the widget to choose another one."))
        case .all:
            (String(localized: "No Connections"), String(localized: "Open Screen Sharing Widgets to sync your Screen Sharing connections."))
        case .network:
            (String(localized: "No Computers Found"), String(localized: "No computer on your local network is sharing its screen."))
        case .group:
            (String(localized: "Empty Group"), String(localized: "Add connections to this group in Screen Sharing."))
        }
    }

    var body: some View {
        Link(destination: readFailure == .accessDenied ? AppGroup.grantAccessURL : AppGroup.openScreenSharingURL) {
            VStack(spacing: 6) {
                Image(systemName: readFailure == nil ? source.symbol : readFailure == .accessDenied ? "lock" : "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(message.title)
                    .font(.headline)
                Text(message.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(4)
        }
    }
}

// MARK: - Placeholder samples

/// Generic machines shown only in the widget gallery / placeholder and Xcode previews.
/// Real data always comes from Screen Sharing via the App Group snapshot.
extension Connection {
    var isSample: Bool { id.hasPrefix("sample-") }

    static let samples: [Connection] = [
        ("Mac mini", "macmini.local", "Mac16,11"),
        ("MacBook Air", "macbook-air.local", "Mac17,3"),
        ("iMac", "imac.local", "iMac24,1"),
        ("Mac Studio", "mac-studio.local", "Mac15,14"),
    ].enumerated().map { index, item in
        Connection(id: "sample-\(index)", displayName: item.0, address: item.1, username: nil,
                   url: URL(string: "vnc://\(item.1)")!, model: item.2, lastConnected: nil)
    }
}

#Preview(as: .systemMedium) {
    ConnectionsWidget()
} timeline: {
    ConnectionsEntry(date: .now, title: ConnectionSource.allTitle, source: .all, connections: Connection.samples, isPlaceholder: false)
}

#Preview(as: .systemSmall) {
    ConnectionsWidget()
} timeline: {
    ConnectionsEntry(date: .now, title: ConnectionSource.allTitle, source: .all, connections: Connection.samples, isPlaceholder: false)
}

#Preview(as: .systemLarge) {
    ConnectionsWidget()
} timeline: {
    ConnectionsEntry(date: .now, title: ConnectionSource.allTitle, source: .all, connections: Connection.samples, isPlaceholder: false)
}
