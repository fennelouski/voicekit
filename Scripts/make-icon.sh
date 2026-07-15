#!/bin/bash
#
# Render the app icon and bake Scripts/AppIcon.icns.
# Run this only when the icon art changes; make-app.sh copies the committed .icns.
#
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swiftc -O -parse-as-library Scripts/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon-2048.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size"             "$TMP/icon-2048.png" --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
    sips -z $((size*2)) $((size*2))     "$TMP/icon-2048.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Scripts/AppIcon.icns
echo "Built Scripts/AppIcon.icns"

# iOS app icon: full-bleed 1024 into the app's asset catalog (supersampled from 2048).
IOSSET="iOS/App/Assets.xcassets/AppIcon.appiconset"
"$TMP/make-icon" "$TMP/icon-ios-2048.png" --ios
sips -z 1024 1024 "$TMP/icon-ios-2048.png" --out "$IOSSET/icon-1024.png" >/dev/null
echo "Built $IOSSET/icon-1024.png"
