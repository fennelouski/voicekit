#!/bin/bash
#
# Install Dictate for everyday use:
#   • copies Dictate.app to /Applications  → Spotlight can find & launch it
#   • installs a launchd LaunchAgent       → relaunches on crash, starts at login
#
# Usage: Scripts/install.sh [--prebuilt build/Dictate.app]
# Uninstall: Scripts/install.sh uninstall
#
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL=studio.100apps.Dictate
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DEST=/Applications/Dictate.app
BIN="$DEST/Contents/MacOS/Dictate"

GUI="gui/$(id -u)"

# bootout is async; bootstrap fails with EIO if the old job is still tearing down.
# Boot it out, then wait until launchd no longer knows the label before returning.
unload() {
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
    for _ in $(seq 1 20); do
        launchctl print "$GUI/$LABEL" >/dev/null 2>&1 || return 0
        sleep 0.2
    done
}

if [ "${1:-}" = "uninstall" ]; then
    unload
    rm -f "$PLIST"
    rm -rf "$DEST"
    echo "Uninstalled Dictate (app, LaunchAgent)."
    exit 0
fi

# Use the verified distribution bundle without rebuilding or replacing its signature.
if [ "${1:-}" = "--prebuilt" ]; then
    SOURCE="${2:-build/Dictate.app}"
elif [ -z "${1:-}" ]; then
    Scripts/make-app.sh
    SOURCE=build/Dictate.app
else
    echo "Usage: Scripts/install.sh [--prebuilt build/Dictate.app]" >&2
    exit 1
fi
Scripts/validate-app.sh "$SOURCE"
INCOMING="/Applications/.Dictate-incoming-$$.app"
ditto "$SOURCE" "$INCOMING"
codesign --verify --deep --strict "$INCOMING"

# Stop the registered job before changing the bundle; keep the previous app for rollback.
unload
for PID in $(pgrep -x Dictate || true); do
    RUNNING=$(ps -p "$PID" -o comm= | sed 's/^ *//')
    if [ "$RUNNING" = "$BIN" ]; then
        kill -TERM "$PID"
        for _ in $(seq 1 50); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$PID" 2>/dev/null; then
            echo "Dictate has not stopped; the existing app is preserved." >&2
            exit 1
        fi
    fi
done
if [ -d "$DEST" ]; then
    OLD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist")
    BACKUP="build/installed-backups/Dictate-$OLD_VERSION-$(date -u +%Y%m%dT%H%M%SZ).app"
    mkdir -p "$(dirname "$BACKUP")"
    mv "$DEST" "$BACKUP"
    echo "Previous app saved to $BACKUP"
fi
mv "$INCOMING" "$DEST"

# KeepAlive.SuccessfulExit=false → relaunch only on a crash (non-zero exit).
# A clean "Quit Dictate" exits 0 and stays quit. RunAtLoad starts it at login.
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLISTEOF

unload
launchctl bootstrap "$GUI" "$PLIST"

echo "Installed. Dictate is running and will relaunch itself if it crashes."
echo "Launch anytime from Spotlight: ⌘Space → \"Dictate\"."
echo "Crash logs (if any): ~/Library/Logs/DiagnosticReports/Dictate-*.ips"
