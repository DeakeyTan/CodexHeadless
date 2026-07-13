#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR"
! rg -q 'rm .*APP_PATH|rm .*STANDALONE_CLI|remove_path' scripts/uninstall.sh
grep -q 'uninstall-session' scripts/uninstall.sh
grep -q 'operationLock.acquire(name: "uninstall-session")' Sources/CodexHeadlessCore/UninstallSessionCoordinator.swift
grep -q 'try deleter.remove(request.installedCLIURL)' Sources/CodexHeadlessCore/UninstallSessionCoordinator.swift
! rg -q 'journalViolation|CleanNormalAssessmentCache' Sources/CodexHeadlessCore/OperationalEvidence*.swift Sources/CodexHeadlessCore/OperationalTransitionDiagnostic.swift
! rg -q 'journalViolation' Sources/CodexHeadlessApp/StatusBarController.swift
grep -q 'operationalEvidenceCache.availability' Sources/CodexHeadlessApp/StatusBarController.swift
grep -q 'safetyAssessmentQueue.async' Sources/CodexHeadlessApp/StatusBarController.swift
grep -q 'test_uninstall_atomicity.sh' .github/workflows/ci.yml
! grep -q 'return "0.9.0-uat.1"' Sources/CodexHeadlessCore/BuildVersion.swift
echo 'r7.2-code-gate-audit=pass'
