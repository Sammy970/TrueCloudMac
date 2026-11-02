#!/usr/bin/env bash
# Builds TrueCloud.app from the Swift package.
# Usage: scripts/build-app.sh [--bundle-moonlight] [--adhoc]
#   --bundle-moonlight  ship /Applications/Moonlight.app inside the bundle
#   --adhoc             sign without any personal certificate (for public downloads)
# OUT=<dir> builds into another folder (default: build).
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE_MOONLIGHT=0
ADHOC=0
for arg in "$@"; do
  case "$arg" in
    --bundle-moonlight) BUNDLE_MOONLIGHT=1 ;;
    --adhoc) ADHOC=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

swift build -c release

APP="${OUT:-build}/TrueCloud.app"
# Version from Config.appVersion; build number = commit count.
VERSION=$(sed -nE 's/.*static let appVersion = "([0-9.]+)".*/\1/p' Sources/Shared/Config.swift)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/TrueCloud" "$APP/Contents/MacOS/TrueCloud"
cp TrueCloud.icns "$APP/Contents/Resources/TrueCloud.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TrueCloud</string>
    <key>CFBundleDisplayName</key><string>TrueCloud</string>
    <key>CFBundleIdentifier</key><string>com.samyakjain.truecloud</string>
    <key>CFBundleExecutable</key><string>TrueCloud</string>
    <key>CFBundleIconFile</key><string>TrueCloud</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Optionally ship Moonlight inside the bundle so users don't need a separate install.
if (( BUNDLE_MOONLIGHT )); then
  cp -R /Applications/Moonlight.app "$APP/Contents/Resources/Moonlight.app"
fi

# Sign with an Apple Development certificate when there is one: macOS ties permissions such as
# Accessibility (needed for the overlay shortcut in fullscreen) to the signature, and an ad-hoc
# signature changes on every build. Falls back to ad-hoc signing. Public builds (--adhoc) never carry
# the personal certificate, which names its owner.
IDENTITY=""
if (( ! ADHOC )); then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Signed with ${IDENTITY:-ad-hoc signature}"
echo "Built $APP"
