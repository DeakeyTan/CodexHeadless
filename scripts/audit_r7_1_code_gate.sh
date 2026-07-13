#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

! grep -Eq 'codex-headless[" ]+off[" ]*\|\|[" ]*true' scripts/uninstall.sh
grep -Eq 'uninstall-check|uninstall-session' scripts/uninstall.sh
grep -q 'case "uninstall-check"' Sources/CodexHeadlessCLI/CLIExecutor.swift
! grep -q 'return "0.9.0-uat.1"' Sources/CodexHeadlessCore/BuildVersion.swift
! grep -q 'printf.*0.9.0-uat.1' scripts/version.sh
grep -q 'headlessManaged' Sources/CodexHeadlessCore/OperationalSafetyPresentation.swift
! rg -q 'cleanNormalCache\.invalidate\(\).{0,120}refreshCleanNormalCache' Sources/CodexHeadlessApp -U
grep -q 'scripts/run_xctest_gate.sh' .github/workflows/ci.yml
echo 'r7.1-code-gate-audit=pass'
