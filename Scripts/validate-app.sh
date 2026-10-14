#!/bin/bash
# Structural verification for development bundles. Not a notarization assertion.
set -euo pipefail
APP="${1:?Usage: Scripts/validate-app.sh path/to/Dictate.app}"
plutil -lint "$APP/Contents/Info.plist"
test -x "$APP/Contents/MacOS/Dictate"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
test -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f "$APP/Contents/Resources/ThirdParty/FluidAudio-LICENSE.txt"
test -f "$APP/Contents/Resources/ThirdParty/Sparkle-LICENSE.txt"
codesign --verify --deep --strict "$APP"
python3 - "$APP" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
assert info['CFBundleIdentifier'] == 'studio.100apps.Dictate'
assert info['CFBundleExecutable'] == 'Dictate'
assert info['LSMinimumSystemVersion'] == '26.0'
for key in ('NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription', 'NSAudioCaptureUsageDescription'):
    assert info.get(key), f'Missing permission disclosure: {key}'
for locale in info['CFBundleLocalizations']:
    resources = app / 'Contents/Resources' / f'{locale}.lproj'
    for filename in ('Localizable.strings', 'InfoPlist.strings'):
        assert (resources / filename).is_file(), f'Missing {locale}/{filename}'
print(f'Validated bundle structure, permission disclosures and {len(info["CFBundleLocalizations"])} locales.')
PY
