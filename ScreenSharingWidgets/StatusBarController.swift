import AppKit

/// Menu bar presence of the host app:
/// - one main item listing every connection (by section) with its state, hover tooltip = summary;
/// - optional pinned items, one per chosen Mac: hover = name + state, click = connect.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private static let pinnedKey = "pinnedConnectionIDs"

    private let model: HostModel
    private let updater: Updater
    private let showWelcome: @MainActor () -> Void
    private let mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var pinnedItems: [String: NSStatusItem] = [:]
    private var snapshot: Snapshot = .empty

    private var pinnedIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.pinnedKey) }
    }

    init(model: HostModel, updater: Updater, showWelcome: @escaping @MainActor () -> Void) {
        self.model = model
        self.updater = updater
        self.showWelcome = showWelcome
        super.init()
        mainItem.autosaveName = "main"
        mainItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "VNC Widget")
        let menu = NSMenu()
        menu.delegate = self
        mainItem.menu = menu
    }

    /// Called on every published snapshot.
    func update(with snapshot: Snapshot) {
        self.snapshot = snapshot
        mainItem.button?.toolTip = summary
        syncPinnedItems()
    }

    // MARK: - Main menu

    private var summary: String {
        let known = snapshot.connections.filter { $0.isOnline != nil }
        guard !known.isEmpty else { return String(localized: "Screen Sharing · \(snapshot.connections.count) connections") }
        let online = known.filter { $0.isOnline == true }.count
        return String(localized: "Screen Sharing · \(online)/\(snapshot.connections.count) online")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if model.writer.readFailure == .accessDenied {
            menu.addItem(actionItem(String(localized: "Allow Access to Screen Sharing…"), #selector(allowAccess)))
            menu.addItem(.separator())
        }

        menu.addItem(.sectionHeader(title: ConnectionSource.allTitle))
        if snapshot.connections.isEmpty {
            menu.addItem(disabled(String(localized: "No Connections")))
        }
        snapshot.connections.forEach { menu.addItem(connectionItem($0)) }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: ConnectionSource.networkTitle))
        if snapshot.network.isEmpty {
            menu.addItem(disabled(String(localized: "No Computers Found")))
        }
        snapshot.network.forEach { menu.addItem(connectionItem($0)) }

        if !snapshot.groups.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "Groups")))
            for group in snapshot.groups {
                let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: ConnectionSource.group(group.id).symbol, accessibilityDescription: nil)
                let submenu = NSMenu()
                let members = snapshot.connections(for: .group(group.id)) ?? []
                if members.isEmpty { submenu.addItem(disabled(String(localized: "Empty Group"))) }
                members.forEach { submenu.addItem(connectionItem($0)) }
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(pinMenuItem())
        menu.addItem(actionItem(String(localized: "Open Screen Sharing"), #selector(openScreenSharing)))
        menu.addItem(actionItem(String(localized: "Refresh"), #selector(refresh), key: "r"))
        let login = actionItem(String(localized: "Open at Login"), #selector(toggleLaunchAtLogin))
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Welcome to Screen Sharing Widgets"), #selector(openWelcome)))
        menu.addItem(actionItem(String(localized: "Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(disabled(model.status))
        menu.addItem(actionItem(String(localized: "Quit Screen Sharing Widgets"), #selector(quit), key: "q"))
    }

    private func connectionItem(_ connection: Connection) -> NSMenuItem {
        let item = NSMenuItem(title: connection.displayName, action: #selector(connect(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = connection.url
        item.subtitle = [connection.subtitle, Self.stateText(connection.isOnline)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        item.image = Self.menuIcon(for: connection)
        item.toolTip = Self.tooltip(for: connection)
        return item
    }

    private func pinMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Pin to Menu Bar"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        let submenu = NSMenu()
        if snapshot.connections.isEmpty { submenu.addItem(disabled(String(localized: "No Connections"))) }
        for connection in snapshot.connections {
            let entry = NSMenuItem(title: connection.displayName, action: #selector(togglePin(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = connection.id
            entry.state = pinnedIDs.contains(connection.id) ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Pinned items

    private func syncPinnedItems() {
        let connections = Dictionary(snapshot.connections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = pinnedIDs.filter { connections[$0] != nil }

        for (id, item) in pinnedItems where !wanted.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            pinnedItems[id] = nil
        }
        for id in wanted {
            guard let connection = connections[id] else { continue }
            let item = pinnedItems[id] ?? makePinnedItem(id: id)
            pinnedItems[id] = item
            guard let button = item.button else { continue }
            button.image = NSImage(systemSymbolName: connection.fallbackSymbol, accessibilityDescription: connection.displayName)
            button.appearsDisabled = connection.isOnline == false
            button.toolTip = Self.tooltip(for: connection)
        }
    }

    private func makePinnedItem(id: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Lets the user ⌘-drag it and keeps its position across launches.
        item.autosaveName = "pinned-\(id)"
        item.button?.target = self
        item.button?.action = #selector(pinnedClicked(_:))
        item.button?.identifier = NSUserInterfaceItemIdentifier(id)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    @objc private func pinnedClicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Right click: small menu to unpin.
            let menu = NSMenu()
            let unpin = NSMenuItem(title: String(localized: "Remove from Menu Bar"), action: #selector(togglePin(_:)), keyEquivalent: "")
            unpin.target = self
            unpin.representedObject = id
            menu.addItem(unpin)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else {
            ScreenSharingLauncher.connect(id: id)
        }
    }

    // MARK: - Actions

    @objc private func connect(_ sender: NSMenuItem) {
        ScreenSharingLauncher.open(sender.representedObject as? URL)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let index = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(id)
        }
        syncPinnedItems()
    }

    @objc private func openScreenSharing() { ScreenSharingLauncher.open(nil) }
    @objc private func refresh() { model.refresh(force: true) }
    @objc private func allowAccess() { model.openPrivacySettings() }
    @objc private func toggleLaunchAtLogin() { model.setLaunchAtLogin(!model.launchAtLogin) }
    @objc private func openWelcome() { showWelcome() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Formatting

    private static func stateText(_ isOnline: Bool?) -> String? {
        switch isOnline {
        case true?: String(localized: "Online")
        case false?: String(localized: "Offline")
        case nil: nil
        }
    }

    static func tooltip(for connection: Connection) -> String {
        [connection.displayName, stateText(connection.isOnline), connection.subtitle]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Product icon fitted in a 28×20 box, faded when offline.
    private static func menuIcon(for connection: Connection) -> NSImage? {
        let box = NSSize(width: 28, height: 20)
        guard let name = connection.iconFileName,
              let url = AppGroup.iconsURL?.appending(path: name),
              let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0
        else {
            return NSImage(systemSymbolName: connection.fallbackSymbol, accessibilityDescription: nil)
        }
        let scale = min(box.width / source.size.width, box.height / source.size.height)
        let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let alpha: CGFloat = connection.isOnline == false ? 0.35 : 1
        return NSImage(size: box, flipped: false) { _ in
            let origin = NSPoint(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
            source.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
    }
}
