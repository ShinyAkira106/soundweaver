#!/bin/bash
# Builds Soundweaver.app and packs it into a drag to install disk image:
#   build/Soundweaver-<version>.dmg
# The window shows the app on the left, an Applications shortcut on the right,
# and the background from Resources/dmg.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
VOLNAME="Soundweaver"
DMG="build/Soundweaver-${VERSION}.dmg"

./build.sh
APP="build/Soundweaver.app"

STAGE="build/dmg-stage"
TEMP="build/temp.dmg"
rm -rf "$STAGE" "$TEMP" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Retina aware background: combine 1x and 2x into one TIFF when tiffutil is available.
if command -v tiffutil >/dev/null 2>&1; then
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png \
    -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
  BG="background.tiff"
else
  cp Resources/dmg/background.png "$STAGE/.background/background.png"
  BG="background.png"
fi

# Volume icon
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# Make sure no stale volume with the same name is mounted
if [[ -d "/Volumes/$VOLNAME" ]]; then
  hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || true
fi

# Leave some headroom for the Finder layout file
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
  -format UDRW -size "${SIZE_MB}m" -ov "$TEMP" >/dev/null
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP" | awk -F'\t' '/\/Volumes\//{print $NF}')
echo "Mounted at $MOUNT_DIR"

# Custom volume icon flag (SetFile ships with the Xcode command line tools)
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_DIR"
fi

# Lay out the Finder window. macOS may ask once to let Terminal control Finder;
# if that is declined the image still works, just without the custom layout.
osascript <<EOF || echo "Note: Finder layout skipped (automation permission not granted)."
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:$BG"
    set position of item "Soundweaver.app" of container window to {160, 190}
    set position of item "Applications" of container window to {480, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

chmod -Rf go-w "$MOUNT_DIR" || true
sync
hdiutil detach "$MOUNT_DIR" >/dev/null || hdiutil detach "$MOUNT_DIR" -force >/dev/null

hdiutil convert "$TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TEMP"
rm -rf "$STAGE"

echo "Created $DMG"
