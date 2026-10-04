#!/bin/zsh
# Build a notarized DMG and its Sparkle appcast into build/release/.
#   ./scripts/release.sh            build, sign (Developer ID), notarize, staple, appcast
#   ./scripts/release.sh --publish  same, then create the GitHub release v<MARKETING_VERSION>
#   ./scripts/release.sh --local    Developer ID build + DMG only (no notarization), for local testing
# Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml first.
# Needs: Developer ID Application certificate, `notarytool store-credentials notary`,
# Sparkle private key in .secrets/sparkle_ed25519_key, gh logged in (for --publish).
set -euo pipefail
cd "${0:A:h}/.."

REPO=axelguilmin/ScreenSharingWidget
TEAM=JMQMP88PPC
NAME="Screen Sharing Widgets"
KEY=.secrets/sparkle_ed25519_key
OUT=build/release
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

publish=false
local_only=false
[[ "${1:-}" == "--publish" ]] && publish=true
[[ "${1:-}" == "--local" ]] && local_only=true

version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)
tag="v$version"
dmg="$OUT/ScreenSharingWidgets-$version.dmg"

[[ -f "$KEY" ]] || { echo "Missing Sparkle private key: $KEY"; exit 1; }
if $publish; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean"; exit 1; }
  git fetch -q origin
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "HEAD is not pushed to origin/main"; exit 1; }
  ! gh release view "$tag" -R "$REPO" >/dev/null 2>&1 || { echo "Release $tag already exists"; exit 1; }
fi

echo "==> $NAME $version ($build)"
DD=$(mktemp -d)
trap 'rm -rf "$DD"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen generate -q
xcodebuild -project ScreenSharingWidgets.xcodeproj -scheme ScreenSharingWidgets -configuration Release \
  -destination generic/platform=macOS -derivedDataPath "$DD" -archivePath "$DD/app.xcarchive" -allowProvisioningUpdates -quiet archive

cat > "$DD/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$DD/app.xcarchive" -exportPath "$DD/export" \
  -exportOptionsPlist "$DD/ExportOptions.plist" -allowProvisioningUpdates -quiet
APP="$DD/export/$NAME.app"
# Keep the temporary copies out of LaunchServices (duplicates confuse the widget gallery).
"$LSR" -u "$DD/app.xcarchive/Products/Applications/$NAME.app" "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"

echo "==> DMG"
mkdir "$DD/dmg"
ditto "$APP" "$DD/dmg/$NAME.app"
ln -s /Applications "$DD/dmg/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$DD/dmg" -fs HFS+ -format UDZO "$dmg"
codesign --sign "Developer ID Application" --timestamp "$dmg"
if $local_only; then
  echo "Local DMG (not notarized) in $OUT"
  exit 0
fi

echo "==> Notarization (a few minutes)"
xcrun notarytool submit "$dmg" --keychain-profile notary --wait
xcrun stapler staple -q "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"

echo "==> Appcast"
"$DD/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --ed-key-file "$KEY" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$tag/" \
  -o "$OUT/appcast.xml" "$OUT"

if $publish; then
  echo "==> GitHub release $tag"
  gh release create "$tag" "$dmg" "$OUT/appcast.xml" -R "$REPO" \
    --target "$(git rev-parse HEAD)" --title "$NAME $version" --generate-notes
else
  echo "Ready in $OUT — run again with --publish to create the GitHub release."
fi
