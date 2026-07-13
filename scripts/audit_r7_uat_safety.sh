#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if rg -n 'command\.contains\("internal-helper"\)|command\.contains\(InternalHelperKind' \
  Sources/CodexHeadlessCore/SleepManager.swift Sources/CodexHeadlessCore/VirtualDisplayManager.swift; then
  echo "Loose helper command substring matching remains in managed-resource observation." >&2
  exit 1
fi

rg -q 'display\.isManagedVirtual' Sources/CodexHeadlessCore/VirtualDisplayManager.swift
rg -q 'expectedDisplayID' Sources/CodexHeadlessCore/VirtualDisplayManager.swift
rg -q 'confirmDialogRestoreSuppression\.beginRestore' Sources/CodexHeadlessApp/StatusBarInteractionCoordinator.swift
rg -q 'temporarilyUnavailable' Sources/CodexHeadlessCore/Models.swift Sources/CodexHeadlessApp/StatusBarController.swift

echo "r7-uat-safety-audit=pass"
