# Screen Sharing Widgets

Your macOS **Screen Sharing** connections, one click away — on the desktop, in the menu bar and in Control Center.

Screen Sharing Widgets mirrors the connections you saved in Apple's Screen Sharing app (macOS 26): **All Connections**, **Network** and your **groups**, with each Mac's product icon and whether it's reachable right now.

> 🇫🇷 Disponible en français et en anglais.

## Features

- **Desktop & Notification Center widgets** — small, medium, large and extra large. Choose the section (All Connections, Network or a group) and the view (icons or list). Click a Mac to connect.
- **Online status** — Bonjour machines are tracked live; IP/hostname connections get a single TCP check on the VNC port every 15 minutes and when the network changes. Offline Macs are dimmed.
- **Menu bar** — every connection by section, with user, host and status. Pin any Mac to the menu bar to get its own icon with a tooltip.
- **Control Center** — add a *Screen Sharing* control to connect to a chosen Mac in one click.

## Requirements

- macOS 26 or later
- Connections saved in Screen Sharing (`/System/Applications/Utilities/Screen Sharing.app`)

## Install

Download the latest `.dmg` from [Releases](../../releases), drag **Screen Sharing Widgets** to Applications and open it once. It lives in the menu bar and starts at login.

Then:
1. Control-click the desktop › **Edit Widgets…** › search for *Screen Sharing*.
2. Control-click the widget › **Edit** to choose the section and view.
3. Optional: Control Center › **Edit Controls** › *Screen Sharing*.

## Privacy & permissions

Everything stays on your Mac — no network calls besides the reachability checks to your own computers.

- **Data from other apps** — the app reads Screen Sharing's saved connections from its preferences. Screen Sharing keeps them in its private container, which macOS only opens to apps with **Full Disk Access**: the welcome window walks you through it (drag its icon into System Settings › Privacy & Security › Full Disk Access, or use +). Until then, the widget shows *No Access to Screen Sharing*.
- **Local network** — used to discover Macs that share their screen (Bonjour `_rfb._tcp`), for the *Network* section.

## How it works

Screen Sharing stores its connections in an undocumented format inside its container. A small menu bar agent reads it, renders the product icons, watches for changes and publishes a snapshot to an App Group that the widget and control read.

⚠️ Because that format is private, a macOS update can break the app. If that happens, the widget shows *Failed to read recent connections* — please open an issue.

The agent is not sandboxed (it needs to read another app's data), so the app is distributed outside the Mac App Store, signed with Developer ID and notarized.

## Build from source

```sh
brew install xcodegen
./scripts/install.sh   # builds Release, installs to ~/Applications, reloads widgets
```

Set your own `DEVELOPMENT_TEAM` and App Group in `project.yml`. When the widget configuration changes, bump `CURRENT_PROJECT_VERSION`, otherwise macOS keeps the old widget description cached.

## License

MIT — see [LICENSE](LICENSE).

*Screen Sharing is a trademark of Apple Inc. This project is not affiliated with Apple.*
