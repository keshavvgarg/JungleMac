#!/bin/zsh
# Builds Jungle.app with the Swift compiler from the Command Line Tools (no Xcode needed).
#   ./build.sh          release build into build/Jungle.app
#   ./build.sh debug    unoptimized build, faster to compile
#   ./build.sh share    release build, zipped into build/Jungle.zip to send to friends
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-release}
APP=build/Jungle.app
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The Command Line Tools ship two module maps that both define SwiftBridging,
# which breaks every Foundation import. An overlay hides the duplicate.
CLT=/Library/Developer/CommandLineTools/usr/include/swift
FLAGS=()
if [[ -f $CLT/bridging.modulemap && -f $CLT/module.modulemap ]]; then
  : > build/empty.modulemap
  cat > build/overlay.yaml <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$CLT",
  "contents": [ { "type": "file", "name": "bridging.modulemap", "external-contents": "$PWD/build/empty.modulemap" } ] } ] }
EOF
  FLAGS+=(-vfsoverlay build/overlay.yaml -Xcc -ivfsoverlay -Xcc build/overlay.yaml)
fi

if [[ $CONFIG == debug ]]; then FLAGS+=(-Onone -g); else FLAGS+=(-O); fi
[[ $CONFIG == share ]] && CONFIG=release SHARE=1

# Apple Silicon only.
swiftc "${FLAGS[@]}" -swift-version 5 -target arm64-apple-macos14.0 \
  -parse-as-library -module-name Jungle \
  Sources/**/*.swift -o "$APP/Contents/MacOS/Jungle"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Jungle</string>
  <key>CFBundleDisplayName</key><string>Jungle</string>
  <key>CFBundleIdentifier</key><string>com.keshavgarg.jungle</string>
  <key>CFBundleExecutable</key><string>Jungle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# App icon, drawn by the app itself.
if [[ ! -f "$APP/Contents/Resources/AppIcon.icns" ]]; then
  ICONSET=build/AppIcon.iconset
  rm -rf $ICONSET && mkdir -p $ICONSET
  "$APP/Contents/MacOS/Jungle" -icon build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ ${SHARE:-} == 1 ]]; then
  rm -f build/Jungle.zip
  ditto -c -k --sequesterRsrc --keepParent "$APP" build/Jungle.zip
  echo "Zipped build/Jungle.zip"
fi
