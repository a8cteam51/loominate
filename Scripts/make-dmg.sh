#!/bin/bash
# Packages build/Loominate.app into a drag-to-Applications disk image.
# Usage: Scripts/make-dmg.sh            (expects a built app; run Scripts/bundle.sh release first)
# Output: dist/Loominate-<version>.dmg
# Window layout is set through Finder scripting, so macOS may ask once to let your terminal
# control Finder. The DMG is signed with the same identity bundle.sh used, when it has one.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Loominate.app"
[[ -d "$APP" ]] || { echo "Build the app first: Scripts/bundle.sh release" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST="$ROOT/dist"
VOLNAME="Loominate"
FINAL="$DIST/Loominate-$VERSION.dmg"
STAGE="$(mktemp -d)"
RW="$STAGE/rw.dmg"
MOUNT="/Volumes/$VOLNAME"
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE"' EXIT
mkdir -p "$DIST" "$STAGE/content/.background"

cp -R "$APP" "$STAGE/content/"
ln -s /Applications "$STAGE/content/Applications"
cp "$ROOT/Assets/dmg-background.png" "$STAGE/content/.background/background.png"

hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE/content" -ov -format UDRW -fs HFS+ "$RW"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$RW"
sleep 1

# Window: 660x400 points, icon view, background, icons at left and right of the arrow.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 860, 560}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set text size of theViewOptions to 13
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "Loominate.app" of container window to {170, 240}
        set position of item "Applications" of container window to {490, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Hide the background folder from view and flush Finder's layout file to disk.
chflags hidden "$MOUNT/.background"
sync
hdiutil detach "$MOUNT" -quiet
rm -f "$FINAL"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL"

IDENTITY="$(codesign -dv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp "$FINAL" 2>/dev/null || codesign --force --sign "$IDENTITY" "$FINAL"
fi
echo "Wrote $FINAL"
