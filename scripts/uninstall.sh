#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${CODEX_HEADLESS_UNINSTALL_APP_PATH:-/Applications/CodexHeadless.app}"
STANDALONE_CLI="${CODEX_HEADLESS_UNINSTALL_STANDALONE_CLI_PATH:-/usr/local/bin/codex-headless}"
LAUNCH_AGENT="${CODEX_HEADLESS_UNINSTALL_LAUNCH_AGENT_PATH:-$HOME/Library/LaunchAgents/com.codexheadless.app.plist}"

refuse() { printf 'Uninstall refused: %s\n' "$1" >&2; exit 2; }
locate_cli() {
  if [[ -n "${CODEX_HEADLESS_UNINSTALL_CLI:-}" ]]; then [[ -x "$CODEX_HEADLESS_UNINSTALL_CLI" ]] && { echo "$CODEX_HEADLESS_UNINSTALL_CLI"; return; }; return 1; fi
  [[ -x "$STANDALONE_CLI" ]] && { echo "$STANDALONE_CLI"; return; }
  [[ -x "$APP_PATH/Contents/MacOS/codex-headless" ]] && { echo "$APP_PATH/Contents/MacOS/codex-headless"; return; }
  [[ -f "$ROOT_DIR/Package.swift" && -x "$ROOT_DIR/.build/debug/codex-headless" ]] && { echo "$ROOT_DIR/.build/debug/codex-headless"; return; }
  return 1
}

CLI="$(locate_cli)" || refuse "no trusted verifier CLI is available."
CLI="$(cd "$(dirname "$CLI")" && pwd -P)/$(basename "$CLI")"
[[ -x "$CLI" ]] || refuse "trusted CLI is not executable."
"$CLI" off || refuse "Restore did not complete; installed recovery tools were preserved."

TEMP_DIR="$(mktemp -d /private/tmp/CodexHeadless-uninstall.XXXXXX)"
chmod 0700 "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
COORDINATOR="$TEMP_DIR/codex-headless"
COPYFILE_DISABLE=1 /bin/cp "$CLI" "$COORDINATOR"
chmod 0755 "$COORDINATOR"
source_hash="$(shasum -a 256 "$CLI" | awk '{print $1}')"
copy_hash="$(shasum -a 256 "$COORDINATOR" | awk '{print $1}')"
[[ "$source_hash" == "$copy_hash" ]] || refuse "temporary coordinator identity mismatch."

exec_args=(uninstall-session --installed-app "$APP_PATH" --installed-cli "$STANDALONE_CLI" --launch-agent "$LAUNCH_AGENT")
"$COORDINATOR" "${exec_args[@]}"
