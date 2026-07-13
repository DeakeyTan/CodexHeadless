#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

virtual_file="Sources/CodexHeadlessCore/VirtualDisplayManager.swift"
journal_coordinator="Sources/CodexHeadlessCore/VirtualDisplayLaunchJournalCoordinator.swift"
helper_file="Sources/CodexHeadlessCLI/CLIInternalHelperCommands.swift"
cli_file="Sources/CodexHeadlessCLI/CLIExecutor.swift"

if ! rg -q 'guard case \.ready\(let displayID\)' "$virtual_file" || \
   ! rg -q 'persistReadyDisplay\(displayID' "$virtual_file" || \
   ! rg -q 'journal\.stage = \.virtualDisplayStarted' "$journal_coordinator"; then
  echo "virtualDisplayStarted is not ordered after accepted display-ready evidence." >&2
  exit 1
fi

if ! rg -q 'CH_PARENT_CONTINUE|validateContinue' \
  Sources/CodexHeadlessCore/VirtualDisplayHelperProtocol.swift "$helper_file"; then
  echo "Virtual helper parent continuation gate is missing." >&2
  exit 1
fi

internal_line="$(rg -n 'args\.first == "internal-helper"' "$cli_file" | cut -d: -f1)"
logger_line="$(rg -n 'let logger = CHLogger\(\)' "$cli_file" | head -1 | cut -d: -f1)"
if [[ -z "$internal_line" || -z "$logger_line" || "$internal_line" -ge "$logger_line" ]]; then
  echo "Internal helpers are not isolated before main file logger creation." >&2
  exit 1
fi

echo "r6-helper-protocol-audit=pass"
