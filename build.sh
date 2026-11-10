#!/bin/zsh
# Builds Snap.app. Usage:
#   ./build.sh            -> build/Snap.app
#   ./build.sh install    -> also copies to /Applications and launches it
#   ./build.sh release    -> also zips it to build/Snap.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Snap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Universal binary: Apple Silicon + Intel, macOS 14+
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14.0 \
    Sources/*.swift -o build/Snap-$arch
done
lipo -create build/Snap-arm64 build/Snap-x86_64 -output "$APP/Contents/MacOS/Snap"
rm build/Snap-arm64 build/Snap-x86_64

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Snap</string>
  <key>CFBundleDisplayName</key><string>Snap</string>
  <key>CFBundleIdentifier</key><string>local.snap.screenshot</string>
  <key>CFBundleExecutable</key><string>Snap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Snap 2>/dev/null || true
  rm -rf /Applications/Snap.app
  cp -R "$APP" /Applications/
  open /Applications/Snap.app
  echo "Installed and launched /Applications/Snap.app"
fi

if [[ "${1:-}" == "release" ]]; then
  rm -f build/Snap.zip
  ditto -c -k --keepParent "$APP" build/Snap.zip
  echo "Created build/Snap.zip"
fi
