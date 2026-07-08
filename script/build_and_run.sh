#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WhisperDrop"
BUNDLE_ID="com.igorsevcenko.WhisperDrop"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ASSET_INFO_PLIST="$DIST_DIR/asset-info.plist"
CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then CONFIGURATION="release"; fi
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
mkdir -p "$APP_RESOURCES/Tokenizer"
cp "$ROOT_DIR/Models/tokenizer/tokenizer.json" "$APP_RESOURCES/Tokenizer/tokenizer.json"
cp "$ROOT_DIR/Models/tokenizer/tokenizer_config.json" "$APP_RESOURCES/Tokenizer/tokenizer_config.json"
cp "$ROOT_DIR/Models/tokenizer/config.json" "$APP_RESOURCES/Tokenizer/config.json"
xcrun actool "$ROOT_DIR/Assets/Assets.xcassets" \
  --compile "$APP_RESOURCES" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon AppIcon \
  --output-partial-info-plist "$ASSET_INFO_PLIST"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>WhisperDrop</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>WhisperDropCommit</key><string>$GIT_COMMIT</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Audio and Video</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.audio</string><string>public.movie</string></array>
  </dict></array>
</dict></plist>
PLIST

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

package_app() {
  local identity="${DEVELOPER_ID_APPLICATION:-}"
  if [[ -n "$identity" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$APP_BUNDLE"
  else
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "warning: no DEVELOPER_ID_APPLICATION set; package is ad hoc signed" >&2
  fi
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  local archive="$DIST_DIR/$APP_NAME-$APP_VERSION-macOS.zip"
  rm -f "$archive"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$archive"
  echo "$archive"
}

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) open_app; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) open_app; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) open_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --package|package) package_app ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2; exit 2 ;;
esac
