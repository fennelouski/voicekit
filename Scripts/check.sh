#!/bin/bash
# Local Apple platform verification. Usage: Scripts/check.sh [all|macos|ios]
set -euo pipefail
cd "$(dirname "$0")/.."

SCOPE="${1:-all}"
if [ "$#" -gt 1 ]; then
    echo "Usage: Scripts/check.sh [all|macos|ios]" >&2
    exit 2
fi
case "$SCOPE" in
    all|macos|ios) ;;
    -h|--help)
        echo "Usage: Scripts/check.sh [all|macos|ios]"
        echo "Default: both platforms. Logs and a summary are saved under build/checks/."
        exit 0 ;;
    *) echo "Unknown scope: $SCOPE. Expected all, macos, or ios." >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    echo "Apple platform checks require macOS with Xcode 26 or newer." >&2
    exit 1
fi

mkdir -p build/checks
REPORT_DIR=$(mktemp -d "$PWD/build/checks/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
exec > >(tee "$REPORT_DIR/check.log") 2>&1
CURRENT_STEP=preflight
finish() {
    result=$?
    trap - EXIT
    if [ "$result" -eq 0 ]; then
        echo "PASS: $SCOPE checks completed."
        echo "PASS: $SCOPE" >> "$REPORT_DIR/summary.txt"
    else
        echo "FAIL: $CURRENT_STEP (exit $result)."
        echo "FAIL: $CURRENT_STEP (exit $result)" >> "$REPORT_DIR/summary.txt"
    fi
    echo "Report: $REPORT_DIR"
    exit "$result"
}
trap finish EXIT

{
    echo "Scope: $SCOPE"
    echo "Started (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Commit: $(git rev-parse HEAD)"
    echo "Working-tree status (checks include uncommitted files):"
    git status --short
} > "$REPORT_DIR/summary.txt"
cat "$REPORT_DIR/summary.txt"

REQUIRED_TOOLS=(git python3 swift xcodebuild xcrun)
if [ "$SCOPE" != ios ]; then
    REQUIRED_TOOLS+=(codesign plutil security)
fi
if [ "$SCOPE" != macos ]; then
    REQUIRED_TOOLS+=(xcodegen)
fi
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing required tool: $tool" >&2
        if [ "$tool" = xcodegen ]; then
            echo "Install XcodeGen with: brew install xcodegen" >&2
        fi
        exit 1
    fi
done

run_step() {
    CURRENT_STEP="$1"
    shift
    echo
    echo "Checking: $CURRENT_STEP"
    "$@"
    echo "PASS: $CURRENT_STEP" >> "$REPORT_DIR/summary.txt"
}

check_shell_syntax() {
    local script
    for script in Scripts/*.sh .githooks/pre-push; do
        bash -n "$script"
    done
}

run_step "Xcode toolchain" xcodebuild -version
run_step "Swift toolchain" swift --version
run_step "Shell syntax" check_shell_syntax
run_step "Working-tree whitespace" git diff --check
run_step "Staged whitespace" git diff --cached --check

if [ "$SCOPE" != ios ]; then
    run_step "macOS deterministic suites" env VOICEKIT_HARDWARE_TESTS=0 swift test
    run_step "macOS development bundle" env BUILD_CONFIGURATION=debug CODE_SIGN_IDENTITY=- Scripts/make-app.sh
    run_step "macOS bundle validation" Scripts/validate-app.sh build/Dictate.app
    run_step "Local timing report tests" python3 Scripts/test-measure-latency.py
fi

if [ "$SCOPE" != macos ]; then
    run_step "iOS project generation" xcodegen generate --spec iOS/project.yml
    run_step "iOS keyboard simulator suites" Scripts/test-ios.sh
fi
