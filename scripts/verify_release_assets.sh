#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
VERSION="$(codex_headless_version)"
ARCH="${CODEX_HEADLESS_ARCH:-universal}"
DIST="$ROOT_DIR/.build/release-assets"
APP="$ROOT_DIR/.build/dist/$ARCH/CodexHeadless.app"
CLI="$ROOT_DIR/.build/dist/$ARCH/release/codex-headless"
ZIP="$DIST/CodexHeadless-$VERSION-$ARCH.zip"
PKG="$DIST/CodexHeadless-$VERSION-$ARCH-unsigned.pkg"

for path in "$APP" "$CLI" "$ZIP" "$PKG" "$DIST/checksums.txt" "$DIST/codex-headless" "$DIST/version.txt"; do
  [[ -e "$path" ]] || { echo "Missing release artifact: $path" >&2; exit 1; }
done

EXPECTED_ARCHS="$ARCH"
[[ "$ARCH" == universal ]] && EXPECTED_ARCHS="arm64 x86_64"
for binary in \
  "$APP/Contents/MacOS/CodexHeadless" \
  "$APP/Contents/MacOS/codex-headless" \
  "$CLI" \
  "$DIST/codex-headless"; do
  actual="$(lipo -archs "$binary")"
  for expected in $EXPECTED_ARCHS; do
    [[ " $actual " == *" $expected "* ]] || { echo "$binary missing $expected: $actual" >&2; exit 1; }
  done
done

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$plist_version" == "$VERSION" ]] || { echo "App version mismatch: $plist_version != $VERSION" >&2; exit 1; }
run_version() { env -u CODEX_HEADLESS_VERSION -u GITHUB_REF_NAME "$1" --version; }
[[ "$(run_version "$CLI")" == "codex-headless $VERSION" ]] || { echo "Standalone CLI version mismatch" >&2; exit 1; }
[[ "$(run_version "$DIST/codex-headless")" == "codex-headless $VERSION" ]] || { echo "Release-assets CLI version mismatch" >&2; exit 1; }
[[ "$(run_version "$APP/Contents/MacOS/codex-headless")" == "codex-headless $VERSION" ]] || { echo "Embedded CLI version mismatch" >&2; exit 1; }

VERIFY_DIR="$(mktemp -d /private/tmp/CodexHeadless-release-verify.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR/zip"
test -x "$VERIFY_DIR/zip/CodexHeadless-$VERSION-$ARCH/CodexHeadless.app/Contents/MacOS/CodexHeadless"
test -x "$VERIFY_DIR/zip/CodexHeadless-$VERSION-$ARCH/codex-headless"
[[ "$(run_version "$VERIFY_DIR/zip/CodexHeadless-$VERSION-$ARCH/codex-headless")" == "codex-headless $VERSION" ]] || { echo "ZIP CLI version mismatch" >&2; exit 1; }
pkgutil --expand "$PKG" "$VERIFY_DIR/pkg"
pkg_version="$(grep '<pkg-info ' "$VERIFY_DIR/pkg/PackageInfo" | sed -n 's/.* version="\([^"]*\)".*/\1/p')"
[[ "$pkg_version" == "$VERSION" ]] || { echo "PKG version mismatch: $pkg_version != $VERSION" >&2; exit 1; }
payload_file="$VERIFY_DIR/payload-files.txt"
pkgutil --payload-files "$PKG" > "$payload_file"
grep -Fq 'Applications/CodexHeadless.app/Contents/MacOS/CodexHeadless' "$payload_file"
grep -Fq 'usr/local/bin/codex-headless' "$payload_file"
if grep -Fq 'CodexHeadlessTestHelper' "$payload_file" || \
   find "$VERIFY_DIR/zip" -name 'CodexHeadlessTestHelper' -print -quit | grep -q .; then
  echo "Test-only helper was included in release artifacts." >&2
  exit 1
fi

(cd "$DIST" && shasum -a 256 -c checksums.txt)
echo "Release verification passed: version=$VERSION arch=$ARCH"
