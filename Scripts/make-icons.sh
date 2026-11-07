#!/bin/bash
# Regenerates the app icon and menu bar icon from the sources in Assets/.
#   Assets/AppIcon-1024.png        full-bleed logomark on transparency (no margins)
#   Assets/loominate-menubar.svg   monochrome black glyph for the menu bar
#   Assets/loominate-logo.svg      logomark + wordmark for the README
# Outputs (committed, so builders do not need ImageMagick):
#   Assets/AppIcon-composed.png    logomark on a full-bleed tile, 1024x1024 (macOS masks it)
#   Assets/AppIcon.icns            all sizes, via iconutil
#   Assets/MenuBarIcon.png / MenuBarIcon@2x.png   18pt template image
# Needs ImageMagick 7 (`brew install imagemagick`) and Xcode CLT's iconutil.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Assets/AppIcon-1024.png"
SVG="$ROOT/Assets/loominate-menubar.svg"
OUT="$ROOT/Assets"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
command -v magick >/dev/null || { echo "ImageMagick (magick) is required"; exit 1; }

# macOS 26 masks every app icon into its own rounded shape and puts legacy icons that carry
# their own margins on a gray backing tile. So the artwork is full-bleed: the tile fills the whole
# 1024 canvas with no rounded corners, and the mark stays inside the area the mask keeps.
# STYLE: purple (purple tile, white mark), white (white tile, purple mark), dark (dark tile, purple mark),
#        transparent (the logomark alone, no tile).
STYLE="${ICON_STYLE:-transparent}"
CANVAS=1024; MARK=960
compose_icon() {   # $1 style, $2 output path
    local style="$1" out="$2" gradient mark
    case "$style" in
        white)  gradient='#FFFFFF-#F4F2FA' ;;
        dark)   gradient='#2F2747-#161126' ;;
        purple) gradient='#9B5CFF-#6A22D8' ;;
        transparent) gradient='none' ;;
        *) echo "unknown style $style"; exit 1 ;;
    esac
    if [[ "$style" == "transparent" ]]; then
        # The logomark alone, no tile: macOS decides what to put behind it.
        magick "$SRC" -resize ${MARK}x${MARK} -background none -gravity center -extent ${CANVAS}x${CANVAS} "$out"
        return
    fi
    if [[ "$style" == "purple" ]]; then
        # White silhouette of the mark; the play triangle (white in the source) becomes a cutout.
        magick "$SRC" -fuzz 6% -transparent '#FFFFFF' -fill white -colorize 100 "$TMP/mark-white.png"
        mark="$TMP/mark-white.png"
    else
        mark="$SRC"
    fi
    magick -size ${CANVAS}x${CANVAS} gradient:"$gradient" \( "$mark" -resize ${MARK}x${MARK} \) \
        -gravity center -compose Over -composite "$out"
}
compose_icon "$STYLE" "$OUT/AppIcon-composed.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    magick "$OUT/AppIcon-composed.png" -resize ${size}x${size} "$ICONSET/icon_${size}x${size}.png"
    magick "$OUT/AppIcon-composed.png" -resize $((size*2))x$((size*2)) "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"

# Menu bar template image: black on transparency, 18 points (18 px and 36 px).
magick -background none -density 96 "$SVG" -resize 18x18 "$OUT/MenuBarIcon.png"
magick -background none -density 192 "$SVG" -resize 36x36 "$OUT/MenuBarIcon@2x.png"
# README logo (2x) in light and dark variants, rendered with macOS's own SVG support so the
# gradient survives; the dark variant is the same SVG with the wordmark fill switched to white.
swift "$ROOT/Scripts/render-svg.swift" "$ROOT/Assets/loominate-logo.svg" "$OUT/loominate-logo.png" 1764 440
sed 's/fill="#000000"/fill="#FFFFFF"/g' "$ROOT/Assets/loominate-logo.svg" > "$TMP/logo-dark.svg"
swift "$ROOT/Scripts/render-svg.swift" "$TMP/logo-dark.svg" "$OUT/loominate-logo-dark.png" 1764 440
echo "Wrote AppIcon-composed.png, AppIcon.icns, MenuBarIcon.png, MenuBarIcon@2x.png, loominate-logo.png, loominate-logo-dark.png in Assets/"
