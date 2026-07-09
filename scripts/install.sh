#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export MACOSX_DEPLOYMENT_TARGET="${CODEX_HEADLESS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-13.0}}"
if [[ -n "${CODEX_HEADLESS_SDKROOT:-}" ]]; then
  export SDKROOT="$CODEX_HEADLESS_SDKROOT"
fi

echo "Building CodexHeadless..."
echo "Deployment target: $MACOSX_DEPLOYMENT_TARGET"
if [[ -n "${SDKROOT:-}" ]]; then
  echo "SDKROOT: $SDKROOT"
else
  echo "SDKROOT: system default"
fi

swift build --build-system native -c release

mkdir -p "$HOME/Library/Application Support/CodexHeadless"
mkdir -p "$HOME/Library/Logs"

CLI_SOURCE="$ROOT_DIR/.build/release/codex-headless"
CLI_TARGET="/usr/local/bin/codex-headless"
APP_BUNDLE_SOURCE="$ROOT_DIR/.build/release/CodexHeadless.app"
APP_TARGET="/Applications/CodexHeadless.app"

bash "$ROOT_DIR/scripts/build_app_bundle.sh"

if [[ ! -w "$(dirname "$CLI_TARGET")" ]]; then
  sudo install -m 0755 "$CLI_SOURCE" "$CLI_TARGET"
else
  install -m 0755 "$CLI_SOURCE" "$CLI_TARGET"
fi

if [[ ! -w "$(dirname "$APP_TARGET")" ]]; then
  sudo rm -rf "$APP_TARGET"
  sudo cp -R "$APP_BUNDLE_SOURCE" "$APP_TARGET"
else
  rm -rf "$APP_TARGET"
  cp -R "$APP_BUNDLE_SOURCE" "$APP_TARGET"
fi

echo "Installed CLI: $CLI_TARGET"
echo "Installed app: $APP_TARGET"
echo "Menu bar executable: $ROOT_DIR/.build/release/CodexHeadless"
