#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
! rg -q 'rm .*APP_PATH|rm .*STANDALONE_CLI|remove_path' "$ROOT_DIR/scripts/uninstall.sh"
grep -q 'mktemp -d /private/tmp/CodexHeadless-uninstall' "$ROOT_DIR/scripts/uninstall.sh"
grep -q 'shasum -a 256' "$ROOT_DIR/scripts/uninstall.sh"
grep -q 'uninstall-session' "$ROOT_DIR/scripts/uninstall.sh"
grep -q 'operationLock.acquire(name: "uninstall-session")' "$ROOT_DIR/Sources/CodexHeadlessCore/UninstallSessionCoordinator.swift"
echo 'uninstall-atomicity-shell-tests=pass'
