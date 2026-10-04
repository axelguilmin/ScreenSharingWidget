import AppKit
import SwiftUI

/// First-launch explanation: what the app does, where to find it, and why macOS asks for permissions.
@MainActor
final class WelcomeWindowController {
    private static let shownKey = "welcomeShown"
    private var window: NSWindow?

    func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.shownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView { [weak self] in self?.window?.close() })
            let window = NSWindow(contentViewController: hosting)
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
}

private struct WelcomeView: View {
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
                Step(symbol: "lock.shield",
                     title: "Permissions",
                     detail: "macOS may ask to let this app access data from other apps (to read your Screen Sharing connections) and to find devices on your local network (to show the Network section). Nothing leaves your Mac.")
            }

            HStack {
                Spacer()
                Button("Get Started", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 520)
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
