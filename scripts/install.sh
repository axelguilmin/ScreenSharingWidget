#!/bin/zsh
# Build Release, install to ~/Applications and make macOS pick up the new widget.
# Bump CURRENT_PROJECT_VERSION in project.yml first when widget configuration changes.
set -euo pipefail
cd "${0:A:h}/.."
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DD=$(mktemp -d)
APP="$HOME/Applications/Screen Sharing Widgets.app"

xcodegen generate -q
xcodebuild -project ScreenSharingWidgets.xcodeproj -scheme ScreenSharingWidgets -configuration Release \
  -derivedDataPath "$DD" -allowProvisioningUpdates -quiet build

pkill -x "Screen Sharing Widgets" || true
pkill -x ScreenSharingWidgetsExtension || true
rm -rf "$APP"
ditto "$DD/Build/Products/Release/Screen Sharing Widgets.app" "$APP"
# Avoid duplicate registrations of the build product (confuses the widget gallery).
"$LSR" -u "$DD/Build/Products/Release/Screen Sharing Widgets.app" || true
rm -rf "$DD"

"$LSR" -f -R "$APP"
open "$APP"
killall chronod NotificationCenter 2>/dev/null || true
echo "Installed: $APP (build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"
