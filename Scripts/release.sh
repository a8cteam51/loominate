#!/bin/bash
# Full distribution build: Developer ID signing, notarization, stapling, DMG.
# Needs, one time:
#   - a "Developer ID Application" certificate in the keychain (SIGN_IDENTITY="Developer ID Application: …")
#   - notarytool credentials stored once with:
#       xcrun notarytool store-credentials "loominate" --apple-id you@automattic.com --team-id TEAMID --password app-specific-password
#     (or an App Store Connect API key; see `xcrun notarytool store-credentials --help`)
#   - .secrets/wpcom.env with the WordPress.com client secret
# Usage: SIGN_IDENTITY="Developer ID Application: Automattic, Inc. (TEAMID)" Scripts/release.sh [notarytool-profile]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-loominate}"
[[ "${SIGN_IDENTITY:-}" == Developer\ ID* ]] || { echo "Set SIGN_IDENTITY to a Developer ID Application identity" >&2; exit 1; }
[[ -f "$ROOT/.secrets/wpcom.env" || -n "${WPCOM_CLIENT_SECRET:-}" ]] || { echo "Missing WordPress.com client secret" >&2; exit 1; }

"$ROOT/Scripts/bundle.sh" release
APP="$ROOT/build/Loominate.app"
codesign --verify --strict --deep "$APP"

echo "Notarizing the app…"
ditto -c -k --keepParent "$APP" "$ROOT/build/Loominate.zip"
xcrun notarytool submit "$ROOT/build/Loominate.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ROOT/build/Loominate.zip"

"$ROOT/Scripts/make-dmg.sh"
DMG="$(ls -t "$ROOT"/dist/Loominate-*.dmg | head -1)"
echo "Notarizing the disk image…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true
echo "Release ready: $DMG"
