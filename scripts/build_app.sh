#!/bin/bash
# Builds Today.app and a release zip into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
# the build number grows with every build
BUILD="$(date +%Y%m%d%H%M)"
APP="build/Today.app"
rm -rf build && mkdir -p build

swift build -c release --disable-sandbox
BIN="$(swift build -c release --disable-sandbox --show-bin-path)/Today"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Today"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"


swift scripts/make_icon.swift build >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Today</string>
  <key>CFBundleDisplayName</key><string>Today</string>
  <key>CFBundleIdentifier</key><string>app.today.mac</string>
  <key>CFBundleExecutable</key><string>Today</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
  </dict>
</dict>
</plist>
PLIST

# Ad-hoc signature: no Apple developer account needed to run on your own Mac.
codesign --force --deep --sign - "$APP"

(cd build && ditto -c -k --sequesterRsrc --keepParent "Today.app" "Today-${VERSION}.zip")
echo "build/Today-${VERSION}.zip (build ${BUILD})"
