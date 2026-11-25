#!/usr/bin/env bash
# Packages build/release/Clippy.app into dist/Clippy-<version>.dmg (drag-to-Applications layout).
# Env: VERSION (default 1.0), NOTARY_PROFILE (optional: notarytool keychain profile to notarize + staple).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0}"
APP="build/release/Clippy.app"
DMG="dist/Clippy-$VERSION.dmg"
mkdir -p dist
[[ -d "$APP" ]] || { echo "Missing $APP. Run scripts/build-app.sh release first." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
echo "==> hdiutil create $DMG"
hdiutil create -volname "Clippy $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

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
