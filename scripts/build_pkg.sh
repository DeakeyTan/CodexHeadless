#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/version.sh"

VERSION="$(codex_headless_version)"
ARCH="${CODEX_HEADLESS_ARCH:-universal}"
export COPYFILE_DISABLE=1
export MACOSX_DEPLOYMENT_TARGET="${CODEX_HEADLESS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-13.0}}"
if [[ -n "${CODEX_HEADLESS_SDKROOT:-}" ]]; then
  export SDKROOT="$CODEX_HEADLESS_SDKROOT"
fi

case "$ARCH" in
  arm64|x86_64|universal) ;;
  *) echo "Unsupported architecture: $ARCH (use arm64, x86_64, or universal)" >&2; exit 1 ;;
esac

echo "Building CodexHeadless package..."
echo "Version: $VERSION"
echo "Architecture: $ARCH"
echo "Deployment target: $MACOSX_DEPLOYMENT_TARGET"

build_arch() {
  local target_arch="$1"
  local scratch="$ROOT_DIR/.build/release-$target_arch"
  local build_args=(build -c release --arch "$target_arch" --scratch-path "$scratch")
  if [[ -n "${CODEX_HEADLESS_BUILD_SYSTEM:-}" ]]; then
    build_args+=(--build-system "$CODEX_HEADLESS_BUILD_SYSTEM")
  fi
  swift "${build_args[@]}"
  local binary_dir="$scratch/$target_arch-apple-macosx/release"
  if [[ ! -x "$binary_dir/CodexHeadless" ]]; then
    binary_dir="$scratch/release"
  fi
  [[ -x "$binary_dir/CodexHeadless" ]] || { echo "Missing $target_arch App executable" >&2; exit 1; }
  [[ -x "$binary_dir/codex-headless" ]] || { echo "Missing $target_arch CLI executable" >&2; exit 1; }
  printf '%s\n' "$binary_dir"
}

ASSEMBLY_DIR="$ROOT_DIR/.build/dist/$ARCH/release"
rm -rf "$ASSEMBLY_DIR"
mkdir -p "$ASSEMBLY_DIR"

if [[ "$ARCH" == "universal" ]]; then
  ARM_DIR="$(build_arch arm64 | tail -n 1)"
  INTEL_DIR="$(build_arch x86_64 | tail -n 1)"
  lipo -create "$ARM_DIR/CodexHeadless" "$INTEL_DIR/CodexHeadless" -output "$ASSEMBLY_DIR/CodexHeadless"
  lipo -create "$ARM_DIR/codex-headless" "$INTEL_DIR/codex-headless" -output "$ASSEMBLY_DIR/codex-headless"
  chmod 0755 "$ASSEMBLY_DIR/CodexHeadless" "$ASSEMBLY_DIR/codex-headless"
else
  SOURCE_DIR="$(build_arch "$ARCH" | tail -n 1)"
  install -m 0755 "$SOURCE_DIR/CodexHeadless" "$ASSEMBLY_DIR/CodexHeadless"
  install -m 0755 "$SOURCE_DIR/codex-headless" "$ASSEMBLY_DIR/codex-headless"
fi
printf '%s\n' "$VERSION" > "$ASSEMBLY_DIR/version.txt"

EXPECTED_ARCHS="$ARCH"
if [[ "$ARCH" == "universal" ]]; then EXPECTED_ARCHS="arm64 x86_64"; fi
for binary in "$ASSEMBLY_DIR/CodexHeadless" "$ASSEMBLY_DIR/codex-headless"; do
  actual="$(lipo -archs "$binary")"
  for expected in $EXPECTED_ARCHS; do
    [[ " $actual " == *" $expected "* ]] || { echo "$binary is missing $expected: $actual" >&2; exit 1; }
  done
done

APP_BUNDLE="$ROOT_DIR/.build/dist/$ARCH/CodexHeadless.app"
CODEX_HEADLESS_RELEASE_DIR="$ASSEMBLY_DIR" \
CODEX_HEADLESS_APP_BUNDLE_PATH="$APP_BUNDLE" \
CODEX_HEADLESS_VERSION="$VERSION" \
bash "$ROOT_DIR/scripts/build_app_bundle.sh"

PKG_WORK_DIR="${CODEX_HEADLESS_PKG_WORK_DIR:-/private/tmp/CodexHeadless-pkg-$ARCH}"
PKG_ROOT="$PKG_WORK_DIR/root"
PKG_OUTPUT_DIR="$ROOT_DIR/.build/pkg"
PKG_OUTPUT="$PKG_OUTPUT_DIR/CodexHeadless-$VERSION-$ARCH-unsigned.pkg"
PKG_TEMP_OUTPUT="$PKG_WORK_DIR/CodexHeadless-$VERSION-$ARCH-unsigned.pkg"
rm -rf "$PKG_ROOT"
rm -f "$PKG_TEMP_OUTPUT"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/usr/local/bin" "$PKG_OUTPUT_DIR"
COPYFILE_DISABLE=1 /bin/cp -R "$APP_BUNDLE" "$PKG_ROOT/Applications/CodexHeadless.app"
install -m 0755 "$ASSEMBLY_DIR/codex-headless" "$PKG_ROOT/usr/local/bin/codex-headless"
find "$PKG_ROOT" -name "._*" -type f -delete
xattr -cr "$PKG_ROOT" 2>/dev/null || true

pkgbuild \
  --root "$PKG_ROOT" \
  --filter "\._.*" \
  --identifier "com.codexheadless.pkg" \
  --version "$VERSION" \
  --install-location "/" \
  --ownership recommended \
  "$PKG_TEMP_OUTPUT"
install -m 0644 "$PKG_TEMP_OUTPUT" "$PKG_OUTPUT"

echo "Built app bundle: $APP_BUNDLE"
echo "Built CLI: $ASSEMBLY_DIR/codex-headless"
echo "Built unsigned package: $PKG_OUTPUT"
