#!/bin/bash
# Build BlinkenDisk and package it as a proper macOS .app bundle.
# Result: ./BlinkenDisk.app — double-clickable, no Dock icon, no Cmd-Tab entry.

set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building release binary..."
swift build -c release

BIN=".build/release/BlinkenDisk"
if [[ ! -x "$BIN" ]]; then
    echo "Build failed: $BIN not found" >&2
    exit 1
fi

APP="BlinkenDisk.app"
echo "==> Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BlinkenDisk"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>BlinkenDisk</string>
    <key>CFBundleDisplayName</key>      <string>BlinkenDisk</string>
    <key>CFBundleIdentifier</key>       <string>local.blinkendisk</string>
    <key>CFBundleExecutable</key>       <string>BlinkenDisk</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>12.0</string>
    <!-- Menu-bar-only: no Dock icon, no menu bar of its own, no Cmd-Tab. -->
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST

echo "==> Done."
echo "    Run with: open $APP"
echo "    or double-click $APP in Finder."
