#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DynAgent"
BUNDLE_ID="dev.dj.DynAgent"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
APP_ICON="$APP_RESOURCES/AppIcon.icns"
SWIFT_ENV=(CLANG_MODULE_CACHE_PATH=/private/tmp/dynagent-clang-cache)

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

env "${SWIFT_ENV[@]}" swift build --disable-sandbox --product DynAgentUI
env "${SWIFT_ENV[@]}" swift build --disable-sandbox --product DynAgent
BUILD_DIR="$(env "${SWIFT_ENV[@]}" swift build --disable-sandbox --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$SOURCE_ICON" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
  cp "$SOURCE_ICON" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$APP_ICON"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' >"$APP_CONTENTS/PkgInfo"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
