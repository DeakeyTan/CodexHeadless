#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

grep -q 'diagnosticLoggingEnabled: false' Sources/CodexHeadlessCore/Models.swift
grep -q 'guard policy.beginWriteIfEnabled() else { return }' Sources/CodexHeadlessCore/Logger.swift
grep -q 'setenv(Self.environmentKey' Sources/CodexHeadlessCore/Logger.swift
grep -q 'DiagnosticLoggingPolicy.shared.setEnabled(false)' Sources/CodexHeadlessApp/StatusBarController.swift
grep -q 'DiagnosticLoggingPolicy.shared.setEnabled(false)' Sources/CodexHeadlessCLI/CLIExecutor.swift
grep -q 'expectedReplacementDisplayID' Sources/CodexHeadlessCore/OperationalEvidence.swift
grep -q 'state.virtualDisplayID.flatMap' Sources/CodexHeadlessCore/OperationalEvidenceAssessor.swift
grep -q 'runtimeMode: HeadlessMode?' Sources/CodexHeadlessCore/OperationalEvidenceCache.swift
grep -q 'operationID: String?' Sources/CodexHeadlessCore/OperationalEvidenceCache.swift
grep -q 'handleVerifiedNormalTransition(reason: "automatic-rollback")' Sources/CodexHeadlessApp/StatusBarInteractionCoordinator.swift
grep -q 'case unverified(String)' Sources/CodexHeadlessCore/UninstallSessionCoordinator.swift
grep -q 'replacementLossConfirmationScheduled' Sources/CodexHeadlessApp/StatusBarInteractionCoordinator.swift
test "$(rg -c 'replacementLossRestoreSubmitted = false' Sources/CodexHeadlessApp/StatusBarInteractionCoordinator.swift)" -ge 2
test "$(rg -c 'Timer\.scheduledTimer' Sources/CodexHeadlessApp/*.swift | awk -F: '{sum += $2} END {print sum+0}')" -eq 2
grep -q 'developmentFallback = "0.9.0-dev"' Sources/CodexHeadlessCore/BuildVersion.swift

echo 'r7.2.1-final-patch-audit=pass'
