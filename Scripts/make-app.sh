#!/bin/bash
#
# Build Dictate.app from the SPM executable target.
# Usage: Scripts/make-app.sh   →  build/Dictate.app
#
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Dictate

APP=build/Dictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dictate "$APP/Contents/MacOS/Dictate"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Prefer a stable signing identity: ad-hoc signatures change every build,
# which makes macOS forget the mic/Accessibility permission grants.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/{print $2; exit}')
if [ -n "${IDENTITY:-}" ]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc (no Apple Development identity found)."
    echo "Note: permission grants reset on each rebuild with ad-hoc signing."
fi

echo "Built $APP — launch with: open $APP"
