#!/usr/bin/env bash
set -euo pipefail

parse_log() {
  local log="$1" summary executed failures skipped
  summary="$(grep -E 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$log" | tail -1 || true)"
  if [[ -z "$summary" ]]; then
    echo 'xctest-gate=fail reason=missing-xctest-summary'
    return 3
  fi
  executed="$(sed -E 's/.*Executed ([0-9]+) tests?.*/\1/' <<<"$summary")"
  failures="$(sed -E 's/.*with ([0-9]+) failures?.*/\1/' <<<"$summary")"
  skipped="$(sed -nE 's/.*with [0-9]+ failures?[^0-9]+([0-9]+) skipped.*/\1/p' <<<"$summary")"
  skipped="${skipped:-0}"
  [[ "$executed" =~ ^[0-9]+$ && "$failures" =~ ^[0-9]+$ ]] || {
    echo 'xctest-gate=fail reason=malformed-xctest-summary'; return 3;
  }
  if (( executed == 0 )); then echo 'xctest-gate=fail reason=zero-executed-tests'; return 4; fi
  if (( failures != 0 )); then echo "xctest-gate=fail reason=test-failures executed=$executed failures=$failures"; return 5; fi
  echo "xctest-gate=pass executed=$executed failures=$failures skipped=$skipped"
}

if [[ "${1:-}" == "--parse-log" ]]; then
  [[ $# == 2 && -f "$2" ]] || { echo 'xctest-gate=fail reason=missing-log'; exit 3; }
  parse_log "$2"
  exit $?
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SCRATCH="${CODEX_HEADLESS_TEST_SCRATCH_PATH:-/private/tmp/CodexHeadless-tests-$(id -u)-$$}"
LOG="${CODEX_HEADLESS_XCTEST_LOG:-$SCRATCH/xctest.log}"
mkdir -p "$SCRATCH" "$(dirname "$LOG")"

echo "developer-dir=$(xcode-select -p)"
xcodebuild -version
swift --version
echo "xctest-scratch=$SCRATCH"
echo "xctest-log=$LOG"

set +e
swift test --scratch-path "$SCRATCH" 2>&1 | tee "$LOG"
test_exit=${PIPESTATUS[0]}
set -e
if (( test_exit != 0 )); then
  echo "xctest-gate=fail reason=swift-test-exit-$test_exit log=$LOG"
  exit "$test_exit"
fi
parse_log "$LOG"
