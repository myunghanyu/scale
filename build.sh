#!/bin/sh
# ./build.sh → build/Scale.app (메뉴바 앱). /Applications로 옮긴 뒤 실행 → "서비스 설치"
set -e
cd "$(dirname "$0")"
APP=build/Scale.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift App.swift -o "$APP/Contents/MacOS/Scale"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.scale.app</string>
  <key>CFBundleName</key><string>Scale</string>
  <key>CFBundleExecutable</key><string>Scale</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$APP"
echo "$APP"
