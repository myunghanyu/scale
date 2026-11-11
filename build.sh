#!/bin/sh
# ./build.sh → build/Scale.app (메뉴바 앱). /Applications로 옮긴 뒤 실행 → "서비스 설치"
set -e
cd "$(dirname "$0")"
APP=build/Scale.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift App.swift -o "$APP/Contents/MacOS/Scale"

# icon: icon.swift → 1024 png → iconset → icns
SET=build/AppIcon.iconset
mkdir -p "$SET" "$APP/Contents/Resources"
swift icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.scale.app</string>
  <key>CFBundleName</key><string>Scale</string>
  <key>CFBundleExecutable</key><string>Scale</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$APP"
echo "$APP"
