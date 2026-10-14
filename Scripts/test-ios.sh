#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Pick an available iPhone, newest OS first; no model/UUID tied to one machine.
SIMULATOR=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
inventory = json.load(sys.stdin)["devices"]
def version(runtime):
    return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[-1].split("-"))
for runtime in sorted((r for r in inventory if "iOS-" in r), key=version, reverse=True):
    if version(runtime)[0] < 26: continue
    for device in inventory[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit(0)
sys.exit("No iOS 26+ iPhone simulator is installed")
')
xcodebuild test -project iOS/DictateiOS.xcodeproj -scheme Dictate \
  -destination "platform=iOS Simulator,id=$SIMULATOR" \
  -derivedDataPath build/ios-tests CODE_SIGNING_ALLOWED=NO \
  -only-testing:DictateKeyboardTests
