# App icon

Source of truth: `ScreenSharingWidgets/AppIcon.icon` (Icon Composer format, editable in
Xcode › Open Developer Tool › Icon Composer). Background is the icon's gradient fill
(#8CC4FF → #7A68F0); the glass shelf and the two Macs are the SVG layers here.

Designed with Claude Design ("Dock of Macs" concept). Render a preview with:

    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
      ScreenSharingWidgets/AppIcon.icon --export-image --output-file icon.png \
      --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
