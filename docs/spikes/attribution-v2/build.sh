#!/bin/zsh
# Builds the attribution spike v2 into ./build (ignored by git). Throwaway prototype, not Farol code.
#   build/attrib2                         the single entry point (see README.md)
#   build/FarolSpikeWeb.app               the spike's own test-load app (same binary, WKWebView role)
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -swift-version 5 -o build/attrib2 Sources/*.swift

APP=build/FarolSpikeWeb.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/attrib2 "$APP/Contents/MacOS/FarolSpikeWeb"
cp stimulus.html "$APP/Contents/Resources/stimulus.html"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.evgiroldo.farol.spike.attributionweb</string>
  <key>CFBundleName</key><string>FarolSpikeWeb</string>
  <key>CFBundleExecutable</key><string>FarolSpikeWeb</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.2</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
codesign --force --sign - build/attrib2 >/dev/null 2>&1
echo "Built $PWD/build/attrib2 and $PWD/$APP"
