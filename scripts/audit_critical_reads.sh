#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

critical_files=(
  Sources/CodexHeadlessCore/EnableWorkflow.swift
  Sources/CodexHeadlessCore/RestoreWorkflow.swift
  Sources/CodexHeadlessCore/RecoveryCoordinator.swift
  Sources/CodexHeadlessCore/SleepManager.swift
  Sources/CodexHeadlessCore/VirtualDisplayManager.swift
  Sources/CodexHeadlessCore/CleanNormalAssessment.swift
  Sources/CodexHeadlessCore/ConfigurationMutationGuard.swift
)

if rg -n 'stateStore\.load\(|configManager\.load\(' "${critical_files[@]}"; then
  echo "error: fallback reads are forbidden in safety-critical resource workflows" >&2
  exit 1
fi

if rg -n 'stateStore\.bestEffortUpdate\(' \
  Sources/CodexHeadlessCore/EnableWorkflow.swift \
  Sources/CodexHeadlessCore/RestoreWorkflow.swift \
  Sources/CodexHeadlessCore/RecoveryCoordinator.swift \
  Sources/CodexHeadlessCore/SleepManager.swift; then
  echo "error: best-effort state writes are forbidden in safety-critical workflow decisions" >&2
  exit 1
fi

echo "critical-read-audit=pass"
