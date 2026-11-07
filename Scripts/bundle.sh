#!/bin/bash
# Builds the Loominate executable with SwiftPM and assembles a signed .app bundle.
# Usage: Scripts/bundle.sh [debug|release]
# Set SIGN_IDENTITY to a code-signing certificate name (see README) for stable
# permission grants across rebuilds. Defaults to ad-hoc signing ("-").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP_NAME="Loominate"
BUNDLE_ID="com.automattic.loominate"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
# Signing identity: $SIGN_IDENTITY, else a dev certificate from Scripts/make-dev-cert.sh if one
# exists, else ad-hoc. A stable identity is what keeps Screen Recording, mic, camera and Keychain
# grants valid across rebuilds; ad-hoc changes identity every build and invalidates them.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    for candidate in "Loominate Dev" "Recorder Dev"; do
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$candidate\""; then
            IDENTITY="$candidate"
            break
        fi
    done
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "warning: no code-signing certificate found; signing ad-hoc. Permissions will reset on every rebuild. Run Scripts/make-dev-cert.sh once." >&2
fi

cd "$ROOT"
# The default "swiftbuild" build system fails without Xcode installed; the
# native one works with Command Line Tools alone.
# pipefail makes a compiler failure abort the script; the grep only hides SwiftPM's deprecation notice.
swift build --build-system native -c "$CONFIG" 2>&1 | { grep -v "has been deprecated" || true; }
BIN_DIR="$(swift build --build-system native -c "$CONFIG" --show-bin-path 2>/dev/null)"
BIN="$BIN_DIR/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
    echo "error: build did not produce $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
for asset in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png; do
    [[ -f "$ROOT/Assets/$asset" ]] && cp "$ROOT/Assets/$asset" "$APP/Contents/Resources/$asset"
done

# WordPress.com OAuth client secret: from the environment or .secrets/wpcom.env (gitignored).
# Written into the built bundle's Info.plist only, before signing seals it.
SECRET="${WPCOM_CLIENT_SECRET:-}"
if [[ -z "$SECRET" && -f "$ROOT/.secrets/wpcom.env" ]]; then
    SECRET="$(grep -E '^WPCOM_CLIENT_SECRET=' "$ROOT/.secrets/wpcom.env" | head -1 | cut -d= -f2- | tr -d "\"'" | tr -d '[:space:]')"
fi
if [[ -n "$SECRET" ]]; then
    /usr/libexec/PlistBuddy -c "Add :LoominateWPComClientSecret string $SECRET" "$APP/Contents/Info.plist"
    echo "Embedded the WordPress.com client secret."
else
    echo "warning: no WordPress.com client secret found (set WPCOM_CLIENT_SECRET or create .secrets/wpcom.env); sign-in is disabled in this build" >&2
fi

CODESIGN_ARGS=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$IDENTITY" == Developer\ ID* ]]; then
    # Distribution builds: hardened runtime and entitlements are required for notarization.
    CODESIGN_ARGS+=(--options runtime --timestamp --entitlements "$ROOT/Scripts/Loominate.entitlements")
fi
codesign "${CODESIGN_ARGS[@]}" "$APP"
echo "Built $APP ($CONFIG), signed with: $IDENTITY"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature)=' || true
