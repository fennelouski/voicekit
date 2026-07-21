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
#    The hardened runtime and timestamp are what notarization requires. Sparkle's embedded
#    helpers need the same treatment (no app entitlements) and must be signed before the app.
Scripts/embed-sparkle.sh "$APP" "$IDENTITY" --options runtime --timestamp
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

# 5. Build the Sparkle update artifact + appcast. Sparkle installs from a zip of the
#    *stapled* app; generate_appcast signs it with the EdDSA key created once via
#    Sparkle's generate_keys (stored in the login keychain). Non-fatal so the DMG still
#    ships if the key isn't set up yet.
GEN=$(find .build -type f -name generate_appcast | head -1)
if [ -n "$GEN" ]; then
    UPDATES=build/updates
    mkdir -p "$UPDATES"
    VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
    ditto -c -k --keepParent "$APP" "$UPDATES/Dictate-$VERSION.zip"
    if "$GEN" --download-url-prefix "https://nathanfennel.com/downloads/" "$UPDATES"; then
        echo "Appcast: $UPDATES/appcast.xml"
        echo "Publish BOTH $UPDATES/Dictate-$VERSION.zip and $UPDATES/appcast.xml to /downloads/ (alongside the DMG)."
    else
        echo "generate_appcast failed — generate the EdDSA key once, then re-run:"
        echo "  \"\$(find .build -name generate_keys | head -1)\"   # prints SUPublicEDKey for Info.plist"
    fi
else
    echo "Sparkle tools not found (run 'swift build' first) — skipped appcast generation."
fi

echo
echo "Built $DMG — upload it to your website."
echo "Final check (should print 'accepted'): spctl -a -t open --context context:primary-signature -v \"$DMG\""
