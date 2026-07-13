#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /private/tmp/CodexHeadless-uninstall-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

make_fixture() {
  local name="$1" off_code="$2" session_code="$3" cli_location="${4:-standalone}"
  local base="$TMP/$name"
  mkdir -p "$base/app/Contents/MacOS" "$base/bin" "$base/home/Library/LaunchAgents" "$base/preserved"
  printf 'config\n' > "$base/preserved/config.json"
  printf 'log\n' > "$base/preserved/app.log"
  local cli="$base/bin/codex-headless"
  [[ "$cli_location" == embedded ]] && cli="$base/app/Contents/MacOS/codex-headless"
  cat > "$cli" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$base/calls"
[[ "\$1" == off ]] && exit $off_code
if [[ "\$1" == uninstall-session ]]; then
  echo "\$0" > "$base/coordinator-path"
  [[ $session_code == 0 ]] || exit $session_code
  shift
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --installed-app|--installed-cli|--launch-agent) rm -rf "\$2"; shift 2 ;;
      *) exit 64 ;;
    esac
  done
  exit 0
fi
exit 1
EOF
  chmod +x "$cli"
  touch "$base/home/Library/LaunchAgents/com.codexheadless.app.plist"
  printf '%s\n' "$base|$cli"
}

run_uninstall() {
  local base="$1" override="$2"
  HOME="$base/home" CODEX_HEADLESS_UNINSTALL_TEST_MODE=1 \
    CODEX_HEADLESS_UNINSTALL_CLI="$override" \
    CODEX_HEADLESS_UNINSTALL_APP_PATH="$base/app" \
    CODEX_HEADLESS_UNINSTALL_STANDALONE_CLI_PATH="$base/bin/codex-headless" \
    CODEX_HEADLESS_UNINSTALL_LAUNCH_AGENT_PATH="$base/home/Library/LaunchAgents/com.codexheadless.app.plist" \
    bash "$ROOT_DIR/scripts/uninstall.sh"
}

fixture="$(make_fixture restore-fails 7 0)"; base="${fixture%%|*}"; cli="${fixture#*|}"
if run_uninstall "$base" "$cli" >/dev/null 2>&1; then echo 'restore failure accepted' >&2; exit 1; fi
test -e "$base/app"; test -e "$base/bin/codex-headless"

fixture="$(make_fixture session-refuses 0 2)"; base="${fixture%%|*}"; cli="${fixture#*|}"
if run_uninstall "$base" "$cli" >/dev/null 2>&1; then echo 'unsafe check accepted' >&2; exit 1; fi
test -e "$base/app"; test -e "$base/bin/codex-headless"

fixture="$(make_fixture safe 0 0)"; base="${fixture%%|*}"; cli="${fixture#*|}"
run_uninstall "$base" "$cli" >/dev/null
test ! -e "$base/app"; test ! -e "$base/bin/codex-headless"
test -e "$base/preserved/config.json"; test -e "$base/preserved/app.log"
test "$(tr '\n' ' ' < "$base/calls")" = "off uninstall-session "
grep -q '^/private/tmp/CodexHeadless-uninstall\.' "$base/coordinator-path"

fixture="$(make_fixture embedded 0 0 embedded)"; base="${fixture%%|*}"; cli="${fixture#*|}"
HOME="$base/home" CODEX_HEADLESS_UNINSTALL_TEST_MODE=1 \
  CODEX_HEADLESS_UNINSTALL_APP_PATH="$base/app" \
  CODEX_HEADLESS_UNINSTALL_STANDALONE_CLI_PATH="$base/bin/codex-headless" \
  CODEX_HEADLESS_UNINSTALL_LAUNCH_AGENT_PATH="$base/home/Library/LaunchAgents/com.codexheadless.app.plist" \
  bash "$ROOT_DIR/scripts/uninstall.sh" >/dev/null
test ! -e "$base/app"

base="$TMP/no-verifier"; mkdir -p "$base/app" "$base/home"
if HOME="$base/home" CODEX_HEADLESS_UNINSTALL_TEST_MODE=1 \
  CODEX_HEADLESS_UNINSTALL_CLI="$base/missing" \
  CODEX_HEADLESS_UNINSTALL_APP_PATH="$base/app" \
  CODEX_HEADLESS_UNINSTALL_STANDALONE_CLI_PATH="$base/missing" \
  bash "$ROOT_DIR/scripts/uninstall.sh" >/dev/null 2>&1; then
  echo 'missing verifier accepted' >&2; exit 1
fi
test -e "$base/app"

echo 'uninstall-safety-shell-tests=pass'
