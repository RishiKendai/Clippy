#!/usr/bin/env bash
# Builds Clippy.app.
#   scripts/build-app.sh debug    -> build/debug/Clippy.app   (native arch, fast; used by `make dev`)
#   scripts/build-app.sh release  -> build/release/Clippy.app (universal arm64 + x86_64)
# Env: VERSION (default 1.0), BUILD_NUMBER (default 1),
#      SIGN_IDENTITY (default: "Clippy Dev" if present in the keychain, else ad-hoc "-").
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ "$CONFIG" == "release" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  ARCH_FLAGS=()
fi

echo "==> swift build -c $CONFIG ${ARCH_FLAGS[*]:-}"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product Clippy
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/$CONFIG/Clippy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clippy" "$APP/Contents/MacOS/Clippy"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signing: a stable identity keeps the Accessibility permission across rebuilds.
# "Clippy Dev" lives in its own keychain (make signing-cert), unlocked here so codesign never prompts.
DEV_KC="$HOME/Library/Keychains/clippy-dev.keychain-db"
SIGN_FLAGS=(--force)
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if [[ -f "$DEV_KC" ]] && security find-identity -p codesigning "$DEV_KC" 2>/dev/null | grep -q '"Clippy Dev"'; then
    security unlock-keychain -p clippy-dev "$DEV_KC"
    SIGN_IDENTITY="Clippy Dev"
    SIGN_FLAGS+=(--keychain "$DEV_KC")
  else
    echo "note: no \"Clippy Dev\" identity (run: make signing-cert); signing ad-hoc, so Accessibility must be re-granted after each build" >&2
    SIGN_IDENTITY="-"
  fi
fi
SIGN_FLAGS+=(--sign "$SIGN_IDENTITY")
# Hardened runtime + timestamp are required for notarization (Developer ID builds).
if [[ "$SIGN_IDENTITY" == Developer\ ID* ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
echo "==> codesign ($SIGN_IDENTITY)"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "==> $APP"
