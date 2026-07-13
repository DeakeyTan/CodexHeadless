#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if rg -n 'controller\.assessCleanNormal\(' \
  Sources/CodexHeadlessApp/StatusBarInteractionCoordinator.swift \
  Sources/CodexHeadlessApp/StatusBarSettingsActions.swift; then
  echo "Authoritative Clean Normal assessment found in a synchronous App action path." >&2
  exit 1
fi

if rg -n 'Shell\.run|/bin/ps|proc_pidpath' Sources/CodexHeadlessApp; then
  echo "Blocking process inspection found in App source." >&2
  exit 1
fi

coordinator="Sources/CodexHeadlessApp/ControllerOperationCoordinator.swift"
metric_line="$(rg -n 'coreFinishToUiMs=' "$coordinator" | cut -d: -f1)"
completion_line="$(rg -n 'completion\?\(result\)' "$coordinator" | cut -d: -f1)"
if [[ -z "$metric_line" || -z "$completion_line" || "$metric_line" -ge "$completion_line" ]]; then
  echo "Core-to-UI latency is measured after completion callback work." >&2
  exit 1
fi

echo "app-responsiveness-audit=pass"
