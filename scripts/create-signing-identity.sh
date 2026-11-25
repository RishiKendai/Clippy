#!/usr/bin/env bash
# Creates the local code-signing identity "Clippy Dev" in its own keychain
# (~/Library/Keychains/clippy-dev.keychain-db).
#
# Why: macOS ties Accessibility permission to the app's signature. Signing every build with the
# same identity keeps the permission across rebuilds. The identity lives in a dedicated keychain
# whose password the build script knows, so codesign never shows a keychain prompt and your login
# keychain is untouched. The key only signs local Clippy builds; it is not a Developer ID.
set -euo pipefail
NAME="Clippy Dev"
KC="$HOME/Library/Keychains/clippy-dev.keychain-db"
KC_PASS="clippy-dev"   # protects a throwaway local signing key only

if [[ -f "$KC" ]] && security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists in $KC."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
P12_PASS="$(openssl rand -hex 16)"
# The keychain only imports PKCS#12 files using the older SHA1/3DES algorithms.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -out "$TMP/id.p12" -passout "pass:$P12_PASS" 2>/dev/null

[[ -f "$KC" ]] || security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings "$KC"          # never auto-lock
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
# Let codesign use the key without asking.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
echo "Created \"$NAME\" in $KC."
