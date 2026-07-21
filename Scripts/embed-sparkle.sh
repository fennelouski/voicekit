#!/bin/bash
#
# Embed + sign Sparkle.framework into a Dictate.app bundle, inside-out.
# codesign does NOT re-sign nested helpers when you re-sign the outer app, so both
# make-app.sh (local identity) and package.sh (Developer ID + runtime + timestamp)
# call this before signing the app itself.
#
# Usage: Scripts/embed-sparkle.sh <APP> <IDENTITY> [extra codesign flags...]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$1"; IDENTITY="$2"; shift 2   # remaining args are extra codesign flags (may be empty)

FW=$(find .build -type d -name Sparkle.framework -path '*macos*' | head -1)
[ -n "$FW" ] || { echo "Sparkle.framework not found — run 'swift build' first." >&2; exit 1; }

mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$FW" "$APP/Contents/Frameworks/"
DEST="$APP/Contents/Frameworks/Sparkle.framework"

# The linked executable references @rpath/Sparkle.framework/...; this rpath resolves it
# once bundled. Harmless if it already exists (re-runs on the same app).
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Dictate" 2>/dev/null || true

# Inside-out: XPC services and helper tools first, framework last. ${arr[@]+...} guard
# keeps `set -u` happy when no extra flags are passed.
V="$DEST/Versions/B"
for helper in "$V"/XPCServices/*.xpc "$V/Autoupdate" "$V/Updater.app"; do
    [ -e "$helper" ] && codesign --force --sign "$IDENTITY" ${@+"$@"} "$helper"
done
codesign --force --sign "$IDENTITY" ${@+"$@"} "$DEST"
