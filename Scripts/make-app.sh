#!/bin/bash
#
# Build Dictate.app from the SPM executable target.
# Usage: Scripts/make-app.sh   →  build/Dictate.app
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in debug|release) ;; *) echo "BUILD_CONFIGURATION must be debug or release" >&2; exit 1 ;; esac
swift build -c "$CONFIGURATION" --product Dictate

APP=build/Dictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIGURATION/Dictate" "$APP/Contents/MacOS/Dictate"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp -R ThirdParty "$APP/Contents/Resources/ThirdParty"

# Localizations: regenerate the .lproj bundles from Scripts/i18n/, then copy them
# into the app's Resources so String(localized:)/SwiftUI resolve against the main bundle.
python3 Scripts/localize.py
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Prefer a stable signing identity: ad-hoc signatures change every build,
# which makes macOS forget the mic/Accessibility permission grants.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/{print $2; exit}')
IDENTITY="${CODE_SIGN_IDENTITY:-${IDENTITY:--}}"   # fall back to ad-hoc

# Embed + sign Sparkle before signing the app, so the app signature covers it.
Scripts/embed-sparkle.sh "$APP" "$IDENTITY"
codesign --force --sign "$IDENTITY" "$APP"
if [ "$IDENTITY" = "-" ]; then
    echo "Signed ad-hoc."
    echo "Note: permission grants reset on each rebuild with ad-hoc signing."
else
    echo "Signed with: $IDENTITY"
fi

echo "Built $APP — launch with: open $APP"
