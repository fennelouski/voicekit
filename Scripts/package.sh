#!/bin/bash
#
# Build a signed, notarized Dictate.dmg for distribution from a website.
# Usage: Scripts/package.sh   →  build/Dictate.dmg
#
# ONE-TIME SETUP — store notary credentials in the keychain:
#   1. Create an app-specific password at appleid.apple.com
#      (Sign-In & Security → App-Specific Passwords).
#   2. Run:
#      xcrun notarytool store-credentials "Dictate-Notary" \
#          --apple-id "you@example.com" --team-id EJLR2RPSV2 --password "abcd-efgh-ijkl-mnop"
#
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: Nathan Fennel (EJLR2RPSV2)"
PROFILE="${NOTARY_PROFILE:-Dictate-Notary}"
APP=build/Dictate.app
DMG=build/Dictate.dmg

# 1. Build the .app (release build + bundle assembly).
Scripts/make-app.sh >/dev/null

# 2. Re-sign for distribution: Developer ID + hardened runtime + entitlements + secure timestamp.
#    The hardened runtime and timestamp are what notarization requires.
codesign --force --options runtime --timestamp \
    --entitlements Scripts/Dictate.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# 3. Notarize the APP and staple its ticket, so the copy the user drags into /Applications
#    verifies even if they're offline on first launch. --wait blocks until Apple finishes
#    (usually 1-5 min). On "Invalid": xcrun notarytool log <id> --keychain-profile "$PROFILE"
ZIP=build/Dictate.zip
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# 4. Package the stapled app as a drag-to-Applications DMG, then notarize + staple the DMG too.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname Dictate -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo
echo "Built $DMG — upload it to your website."
echo "Final check (should print 'accepted'): spctl -a -t open --context context:primary-signature -v \"$DMG\""
