#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${CODEX_HEADLESS_RELEASE_DIR:-$ROOT_DIR/.build/release}"
APP_EXECUTABLE_SOURCE="$RELEASE_DIR/CodexHeadless"
CLI_EXECUTABLE_SOURCE="$RELEASE_DIR/codex-headless"
APP_BUNDLE_SOURCE="${CODEX_HEADLESS_APP_BUNDLE_PATH:-$RELEASE_DIR/CodexHeadless.app}"
ICON_SOURCE="$ROOT_DIR/icon.png"
MIN_MACOS_VERSION="${CODEX_HEADLESS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-13.0}}"
APP_VERSION="${CODEX_HEADLESS_VERSION:-0.5}"

if [[ ! -x "$APP_EXECUTABLE_SOURCE" ]]; then
  echo "Missing release executable: $APP_EXECUTABLE_SOURCE" >&2
  echo "Run: swift build --build-system native -c release" >&2
  exit 1
fi

if [[ ! -x "$CLI_EXECUTABLE_SOURCE" ]]; then
  echo "Missing release helper executable: $CLI_EXECUTABLE_SOURCE" >&2
  echo "Run: swift build --build-system native -c release" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE_SOURCE"
mkdir -p "$APP_BUNDLE_SOURCE/Contents/MacOS"
mkdir -p "$APP_BUNDLE_SOURCE/Contents/Resources"

install -m 0755 "$APP_EXECUTABLE_SOURCE" "$APP_BUNDLE_SOURCE/Contents/MacOS/CodexHeadless"
install -m 0755 "$CLI_EXECUTABLE_SOURCE" "$APP_BUNDLE_SOURCE/Contents/MacOS/codex-headless"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_BUNDLE_SOURCE/Contents/Resources/icon.png"
else
  echo "Warning: icon.png not found; app bundle will not include a custom icon." >&2
fi

cat > "$APP_BUNDLE_SOURCE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CodexHeadless</string>
    <key>CFBundleIconFile</key>
    <string>icon.png</string>
    <key>CFBundleIdentifier</key>
    <string>com.codexheadless.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CodexHeadless</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built app bundle: $APP_BUNDLE_SOURCE"
