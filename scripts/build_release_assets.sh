#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/version.sh"

VERSION="$(codex_headless_version)"
ARCH="${CODEX_HEADLESS_ARCH:-universal}"
CODEX_HEADLESS_VERSION="$VERSION" CODEX_HEADLESS_ARCH="$ARCH" bash scripts/build_pkg.sh

DIST_DIR="$ROOT_DIR/.build/release-assets"
SOURCE_DIR="$ROOT_DIR/.build/dist/$ARCH"
ZIP_ROOT="$DIST_DIR/CodexHeadless-$VERSION-$ARCH"
rm -rf "$ZIP_ROOT"
mkdir -p "$ZIP_ROOT" "$DIST_DIR"
ditto --noextattr --noqtn --norsrc "$SOURCE_DIR/CodexHeadless.app" "$ZIP_ROOT/CodexHeadless.app"
install -m 0755 "$SOURCE_DIR/release/codex-headless" "$ZIP_ROOT/codex-headless"
install -m 0755 "$SOURCE_DIR/release/codex-headless" "$DIST_DIR/codex-headless"
install -m 0644 README.md "$ZIP_ROOT/README.md"
printf '%s\n' "$VERSION" > "$ZIP_ROOT/version.txt"
printf '%s\n' "$VERSION" > "$DIST_DIR/version.txt"

ZIP_PATH="$DIST_DIR/CodexHeadless-$VERSION-$ARCH.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$ZIP_ROOT" "$ZIP_PATH"
cp "$ROOT_DIR/.build/pkg/CodexHeadless-$VERSION-$ARCH-unsigned.pkg" "$DIST_DIR/"

cd "$DIST_DIR"
shasum -a 256 "CodexHeadless-$VERSION-$ARCH.zip" "CodexHeadless-$VERSION-$ARCH-unsigned.pkg" codex-headless > checksums.txt
CODEX_HEADLESS_VERSION="$VERSION" CODEX_HEADLESS_ARCH="$ARCH" bash "$ROOT_DIR/scripts/verify_release_assets.sh"
echo "Release assets: $DIST_DIR"
