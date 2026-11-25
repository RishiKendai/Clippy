#!/usr/bin/env bash
# Packages build/release/Clippy.app into dist/Clippy.dmg with the usual drag-to-install window:
# Clippy's icon on the left, an arrow, the Applications folder on the right.
# The window layout is set by Finder (AppleScript), so the first run asks to let your
# terminal control Finder (System Settings → Privacy & Security → Automation).
# Env: NOTARY_PROFILE (optional: notarytool keychain profile to notarize + staple).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/release/Clippy.app"
DMG="dist/Clippy.dmg"
VOLNAME="Clippy"
[[ -d "$APP" ]] || { echo "Missing $APP. Run scripts/build-app.sh release first." >&2; exit 1; }
mkdir -p dist

WORK="$(mktemp -d)"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 1. Stage: the app, an Applications link, and the background (1x + 2x in one TIFF).
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/make-dmg-background.swift "$WORK/bg.png" 1
swift scripts/make-dmg-background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

# 2. Writable image, mounted where Finder can style it. A stale "Clippy" volume would confuse Finder.
[[ -d "/Volumes/$VOLNAME" ]] && hdiutil detach "/Volumes/$VOLNAME" -quiet -force 2>/dev/null || true
echo "==> hdiutil create (read-write)"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | sed -n 's|^/dev/[^ ]*[[:space:]]*Apple_HFS[[:space:]]*||p' | head -1)"
[[ -d "$MOUNT" ]] || { echo "Could not mount the image." >&2; exit 1; }

# 3. Window layout. Must match the positions in scripts/make-dmg-background.swift.
echo "==> styling the window in Finder"
osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Clippy.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
# Volume icon (desktop / sidebar while the DMG is open). Added after Finder is done with the
# window, which otherwise drops it. SetFile ships with the Command Line Tools.
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
if command -v SetFile >/dev/null; then SetFile -a C "$MOUNT"; fi
sync
rm -rf "$MOUNT/.fseventsd"
hdiutil detach "$MOUNT" -quiet
MOUNT=""

# 4. Compress to the final read-only image.
rm -f "$DMG"
echo "==> hdiutil convert $DMG"
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
DEV_KC="$HOME/Library/Keychains/clippy-dev.keychain-db"
if [[ "$IDENTITY" == "Clippy Dev" && -f "$DEV_KC" ]]; then
  security unlock-keychain -p clippy-dev "$DEV_KC"
  codesign --force --keychain "$DEV_KC" --sign "$IDENTITY" "$DMG"
elif [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> notarizing ($NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
