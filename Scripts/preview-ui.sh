#!/bin/bash
# Isolated development UI; never replaces a running Dictate or touches its data.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-recovery}"
case "$MODE" in recovery|vocabulary|cleanup) ;; *) echo 'Use recovery, vocabulary, or cleanup' >&2; exit 1 ;; esac
BUILD_CONFIGURATION=debug CODE_SIGN_IDENTITY=- Scripts/make-app.sh
PREVIEW=build/DictatePreview.app
rm -rf "$PREVIEW"
ditto build/Dictate.app "$PREVIEW"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier studio.100apps.Dictate.preview' "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Dictate Preview' "$PREVIEW/Contents/Info.plist"
codesign --force --sign - "$PREVIEW"
open -n "$PREVIEW" --args "--preview-$MODE"
