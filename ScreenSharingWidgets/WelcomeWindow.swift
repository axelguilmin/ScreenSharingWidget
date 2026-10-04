import AppKit
import SwiftUI

/// First-launch explanation: what the app does, where to find it, and the Full Disk Access it needs.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private static let doneKey = "welcomeDone"
    private let model: HostModel
    private var window: NSWindow?

    init(model: HostModel) {
        self.model = model
    }

    /// Until the user dismisses it, and on every launch while Screen Sharing's data can't be read.
    /// Granting Full Disk Access quits and reopens the app: the window comes back with the access confirmed.
    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.doneKey) || !model.hasScreenSharingAccess else { return }
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(model: model) { [weak self] in
                self?.markDone()
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.delegate = self
            window.title = String(localized: "Welcome to Screen Sharing Widgets")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Agent app (no Dock icon): bring the window forward explicitly.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func markDone() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
    }

    // Close button only: windowWillClose also fires when the app quits (e.g. Quit & Reopen
    // after granting Full Disk Access), which must not count as dismissing the window.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        markDone()
        return true
    }
}

private struct WelcomeView: View {
    let model: HostModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Screen Sharing Widgets")
                        .font(.title2.weight(.semibold))
                    Text("Your Screen Sharing connections, one click away.")
                        .foregroundStyle(.secondary)
                }
            }

            AccessCard(model: model)

            VStack(alignment: .leading, spacing: 14) {
                Step(symbol: "square.grid.2x2",
                     title: "Desktop widget",
                     detail: "Control-click the desktop, choose Edit Widgets, then search for Screen Sharing. Control-click a widget and choose Edit to pick All Connections, Network or a group.")
                Step(symbol: "menubar.rectangle",
                     title: "Menu bar",
                     detail: "Click the menu bar icon to see all your connections. Use Pin to Menu Bar to give a computer its own icon.")
                Step(symbol: "switch.2",
                     title: "Control Center",
                     detail: "In Control Center, click Edit Controls and add Screen Sharing to connect to a computer in one click.")
                Step(symbol: "network",
                     title: "Local network",
                     detail: "macOS may ask to let this app find devices on your local network, to show the Network section. Nothing leaves your Mac.")
            }

            HStack {
                Spacer()
                // The app is useless without access: the close button still dismisses the window.
                Button("Get Started", action: onDone)
                    .keyboardShortcut(model.hasScreenSharingAccess ? .defaultAction : nil)
                    .disabled(!model.hasScreenSharingAccess)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

/// Full Disk Access is the only way to read Screen Sharing's private container (macOS doesn't prompt for it).
private struct AccessCard: View {
    let model: HostModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.hasScreenSharingAccess ? "checkmark.circle.fill" : "lock.circle.fill")
                .font(.title)
                .foregroundStyle(model.hasScreenSharingAccess ? .green : .orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.hasScreenSharingAccess ? "Access to Screen Sharing granted" : "Allow access to Screen Sharing")
                    .font(.headline)
                if model.hasScreenSharingAccess {
                    Text("Your connections are synced with the widget.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Screen Sharing keeps your connections in its private data. To read them, open Full Disk Access and drag this icon into the list (or click + and choose Screen Sharing Widgets in Applications), turn it on, then choose Quit & Reopen. It's only used to read Screen Sharing's connections.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Open Full Disk Access Settings") { model.openPrivacySettings() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        // Dropping the app bundle on the Full Disk Access list adds it, like the + button.
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                            .help("Drag into the Full Disk Access list")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        .animation(.default, value: model.hasScreenSharingAccess)
    }
}

private struct Step: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
