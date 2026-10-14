#!/bin/bash
# Builds SnapMark.app into ./build and (optionally) copies it to /Applications.
#   ./build.sh            build only
#   ./build.sh install    build and copy to /Applications
# Set SIGN_ID to a signing identity (e.g. "Apple Development: you@example.com")
# to keep macOS permissions across rebuilds. The default is an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnapMark"

APP=build/SnapMark.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnapMark"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x SnapMark 2>/dev/null || true
    rm -rf /Applications/SnapMark.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/SnapMark.app"
    open /Applications/SnapMark.app
fi
