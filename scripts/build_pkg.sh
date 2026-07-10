#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${CODEX_HEADLESS_VERSION:-0.5}"
ARCH="${CODEX_HEADLESS_ARCH:-arm64}"
export COPYFILE_DISABLE=1
export MACOSX_DEPLOYMENT_TARGET="${CODEX_HEADLESS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-13.0}}"
if [[ -n "${CODEX_HEADLESS_SDKROOT:-}" ]]; then
  export SDKROOT="$CODEX_HEADLESS_SDKROOT"
fi

echo "Building CodexHeadless package..."
echo "Version: $VERSION"
echo "Architecture: $ARCH"
echo "Deployment target: $MACOSX_DEPLOYMENT_TARGET"
if [[ -n "${SDKROOT:-}" ]]; then
  echo "SDKROOT: $SDKROOT"
else
  echo "SDKROOT: system default"
fi

swift build -c release --arch "$ARCH" --build-system native

RELEASE_DIR="$ROOT_DIR/.build/${ARCH}-apple-macosx/release"
if [[ ! -x "$RELEASE_DIR/CodexHeadless" || ! -x "$RELEASE_DIR/codex-headless" ]]; then
  RELEASE_DIR="$ROOT_DIR/.build/release"
fi

APP_EXECUTABLE="$RELEASE_DIR/CodexHeadless"
CLI_EXECUTABLE="$RELEASE_DIR/codex-headless"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Missing app executable: $APP_EXECUTABLE" >&2
  exit 1
fi
if [[ ! -x "$CLI_EXECUTABLE" ]]; then
  echo "Missing CLI executable: $CLI_EXECUTABLE" >&2
  exit 1
fi

if command -v lipo >/dev/null 2>&1; then
  if ! lipo -archs "$APP_EXECUTABLE" | tr ' ' '\n' | grep -qx "$ARCH"; then
    echo "App executable does not contain requested architecture: $ARCH" >&2
    lipo -archs "$APP_EXECUTABLE" >&2
    exit 1
  fi
  if ! lipo -archs "$CLI_EXECUTABLE" | tr ' ' '\n' | grep -qx "$ARCH"; then
    echo "CLI executable does not contain requested architecture: $ARCH" >&2
    lipo -archs "$CLI_EXECUTABLE" >&2
    exit 1
  fi
fi

PKG_WORK_DIR="${CODEX_HEADLESS_PKG_WORK_DIR:-/private/tmp/CodexHeadless-pkg}"
PKG_ROOT="$PKG_WORK_DIR/root"
PKG_OUTPUT_DIR="$ROOT_DIR/.build/pkg"
PKG_OUTPUT="$PKG_OUTPUT_DIR/CodexHeadless-$VERSION-$ARCH-unsigned.pkg"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_OUTPUT_DIR"
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"

CODEX_HEADLESS_RELEASE_DIR="$RELEASE_DIR" \
CODEX_HEADLESS_APP_BUNDLE_PATH="$PKG_ROOT/Applications/CodexHeadless.app" \
CODEX_HEADLESS_VERSION="$VERSION" \
bash "$ROOT_DIR/scripts/build_app_bundle.sh"

install -m 0755 "$CLI_EXECUTABLE" "$PKG_ROOT/usr/local/bin/codex-headless"
find "$PKG_ROOT" -name "._*" -type f -delete
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.provenance "$PKG_ROOT" 2>/dev/null || true
  xattr -cr "$PKG_ROOT"
fi

pkgbuild \
  --root "$PKG_ROOT" \
  --filter "\._.*" \
  --identifier "com.codexheadless.pkg" \
  --version "$VERSION" \
  --install-location "/" \
  --ownership recommended \
  "$PKG_OUTPUT"

echo "Built unsigned package: $PKG_OUTPUT"
