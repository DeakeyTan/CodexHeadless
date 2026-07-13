#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d /private/tmp/CodexHeadless-xctest-parser.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

expect_pass() { bash "$ROOT_DIR/scripts/run_xctest_gate.sh" --parse-log "$1" | grep -q 'xctest-gate=pass'; }
expect_fail() { if bash "$ROOT_DIR/scripts/run_xctest_gate.sh" --parse-log "$1" >/dev/null; then return 1; fi; }

printf "Test Suite passed\n Executed 145 tests, with 0 failures (0 unexpected)\n" > "$TMP/pass"
expect_pass "$TMP/pass"
printf "Executed 0 tests, with 0 failures\n" > "$TMP/zero"; expect_fail "$TMP/zero"
printf "Executed 145 tests, with 1 failure\n" > "$TMP/fail"; expect_fail "$TMP/fail"
printf "Build complete\n" > "$TMP/missing"; expect_fail "$TMP/missing"
cat > "$TMP/mixed" <<'EOF'
Executed 4 tests, with 0 failures
Executed 145 tests, with 0 failures (0 unexpected)
Test run with 0 tests in 0 suites passed
EOF
result="$(bash "$ROOT_DIR/scripts/run_xctest_gate.sh" --parse-log "$TMP/mixed")"
[[ "$result" == *'executed=145 failures=0'* ]]
printf "Executed many tests, with no failures\n" > "$TMP/malformed"; expect_fail "$TMP/malformed"
echo 'xctest-gate-parser-tests=pass'
