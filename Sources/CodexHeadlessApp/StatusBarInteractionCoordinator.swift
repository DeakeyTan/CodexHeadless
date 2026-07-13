import AppKit
import CodexHeadlessCore

extension StatusBarController {
    func configureHotkeysIfNeeded(force: Bool = false) {
        let hotkeys = configManager.load().effectiveHotkeys
        guard force || lastHotkeysEnabled != hotkeys.enabled else {
            return
        }
        lastHotkeysEnabled = hotkeys.enabled
        hotkeyManager.onAction = { [weak self] action in
            self?.handleHotkey(action)
        }
        hotkeyManager.configure(hotkeys)
        logger.info("[Hotkey] Config enabled=\(hotkeys.enabled), enable=\(hotkeys.enable.displayString), confirm=\(hotkeys.confirm.displayString), restore=\(hotkeys.restore.displayString)")
    }

    func syncConfirmDialogWithState() {
        let state = stateStore.load()
        if confirmDialogRestoreSuppression.shouldPresent(runtimeMode: state.mode) {
            let config = configManager.load().effectiveConfirmDialog
            if confirmDialogController.isVisible {
                confirmDialogController.update(deadline: state.rollbackDeadline)
            } else {
                showConfirmDialogIfNeeded(state: state, config: config)
            }
        } else if confirmDialogController.isVisible {
            confirmDialogController.dismiss(reason: "state=\(state.mode.rawValue)")
        }
    }

    func syncRestoreOverlayWithState() {
        let state = stateStore.load()
        restoreOverlayController.update(state: state)
    }

    func showConfirmDialogIfNeeded(state: RuntimeState, config: ConfirmDialogConfig) {
        guard state.mode == .confirmRequired, config.enabled else {
            return
        }
        confirmDialogController.show(
            deadline: state.rollbackDeadline,
            config: config,
            onConfirm: { [weak self] in
                self?.handleConfirmRequested(source: "dialog")
            },
            onRollback: { [weak self] in
                self?.handleRestoreRequested(source: "dialog")
            }
        )
    }

    func handleHotkey(_ action: HotkeyAction) {
        switch action {
        case .enable:
            handleEnableRequested(source: "hotkey")
        case .confirm:
            handleConfirmRequested(source: "hotkey")
        case .restore:
            handleRestoreRequested(source: "hotkey")
        }
    }

    func handleEnableRequested(source: String) {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        transientOperationTitle = "Checking safety..."
        updateTitle()
        let state = stateStore.load()
        logger.info("[State] enable requested, source=\(source), current=\(state.mode.rawValue)")
        guard state.mode == .normal else {
            transientOperationTitle = nil
            updateTitle()
            logger.warn("[State] enable ignored, source=\(source), current=\(state.mode.rawValue)")
            return
        }
        logger.info("[Perf] enable requestToSubmissionMs=\((DispatchTime.now().uptimeNanoseconds - requestedAt) / 1_000_000)")
        operationalEvidenceCache.clear()
        expectedOperationalOperationID = nil
        replacementLossSuspect = nil
        enableHeadlessFromSource(source)
    }

    func schedulePeriodicMaintenance() {
        let state = stateStore.load()
        let uptime = ProcessInfo.processInfo.systemUptime
        let actions = maintenancePolicy.actions(
            state: state,
            uptime: uptime,
            lastNormalAssessmentUptime: lastNormalAssessmentUptime,
            lastHeadlessReconcileUptime: lastHeadlessReconcileUptime
        )
        for action in actions {
            switch action {
            case .refreshCleanNormalCache:
                lastNormalAssessmentUptime = uptime
                refreshCleanNormalCache(reason: "periodic-normal")
            case .reconcileManagedResources:
                lastHeadlessReconcileUptime = uptime
                operationCoordinator.submitPeriodic { [weak self] in
                    guard let self else { return }
                    guard self.operationalEvidenceCache.beginRefresh() else { return }
                    do {
                        let evidence = try self.controller.reconcileAndAssessOperationalEvidence(source: .periodicReconcile)
                        self.completeOperationalEvidence(evidence)
                    } catch {
                        self.operationalEvidenceCache.failRefresh(error.localizedDescription)
                        DispatchQueue.main.async { [weak self] in self?.requestMenuRefresh() }
                    }
                }
            case .refreshCooldown:
                operationCoordinator.submitPeriodic { [weak self] in self?.controller.refreshPhaseIfNeeded() }
            case .checkRollback:
                operationCoordinator.submitPeriodic { [weak self] in
                    guard let self else { return }
                    self.controller.rollbackIfNeeded()
                    if self.stateStore.load().mode == .normal {
                        DispatchQueue.main.async { [weak self] in self?.handleVerifiedNormalTransition(reason: "automatic-rollback") }
                    }
                }
            case .resumePausedRestore:
                operationCoordinator.submitPeriodic { [weak self] in self?.controller.continuePausedRestoreIfReady() }
            }
        }
    }

    func handleReplacementContinuity(_ evidence: OperationalEvidence) {
        let state = stateStore.load()
        guard !replacementLossRestoreSubmitted,
              let candidate = ReplacementLossSuspect(state: state, evidence: evidence) else {
            replacementLossSuspect = nil
            return
        }
        if replacementLossSuspect != candidate { replacementLossSuspect = candidate }
        guard !replacementLossConfirmationScheduled else { return }
        replacementLossConfirmationScheduled = true
        transientOperationTitle = "Replacement display lost. Verifying..."
        updateTitle()
        safetyAssessmentQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let result = Result { try self.controller.reconcileAndAssessOperationalEvidence(source: .periodicReconcile) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.replacementLossConfirmationScheduled = false
                self.transientOperationTitle = nil
                switch result {
                case .success(let confirmation):
                    self.completeOperationalEvidence(confirmation)
                    let currentState = self.stateStore.load()
                    guard self.replacementLossSuspect == candidate,
                          candidate.stillMatches(state: currentState, evidence: confirmation),
                          !self.replacementLossRestoreSubmitted else { return }
                    self.replacementLossRestoreSubmitted = true
                    self.replacementLossSuspect = nil
                    self.transientOperationTitle = "Replacement display was lost. Restoring Normal Mode..."
                    self.runRestoreControllerOperation(name: "replacement loss restore", source: "replacement-loss")
                case .failure:
                    self.replacementLossSuspect = nil
                    self.requestMenuRefresh()
                }
            }
        }
    }

    func handleConfirmRequested(source: String) {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        transientOperationTitle = "Confirming Headless Mode..."
        updateTitle()
        let state = stateStore.load()
        logger.info("[State] confirm requested, source=\(source), current=\(state.mode.rawValue)")
        guard state.mode == .confirmRequired else {
            transientOperationTitle = nil
            updateTitle()
            logger.warn("[State] confirm ignored, source=\(source), current=\(state.mode.rawValue)")
            return
        }
        logger.info("[Perf] confirm requestToSubmissionMs=\((DispatchTime.now().uptimeNanoseconds - requestedAt) / 1_000_000)")
        runControllerOperation(name: "confirm", source: source, operation: { [controller] in
            guard controller.confirm() else {
                throw CodexHeadlessError.managedResource(message: "Confirm was not applied because the runtime state changed.")
            }
        }, completion: { [weak self] result in
            guard case .success = result else { return }
            self?.confirmDialogRestoreSuppression.clear()
            self?.confirmDialogController.dismiss(reason: "confirmed by \(source)")
        })
    }

    func handleRestoreRequested(source: String) {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        transientOperationTitle = "Restoring Normal Mode..."
        updateTitle()
        let state = stateStore.load()
        logger.info("[State] restore requested, source=\(source), current=\(state.mode.rawValue)")
        if state.mode == .confirmRequired {
            confirmDialogRestoreSuppression.beginRestore()
            confirmDialogController.dismiss(reason: "Restore requested by \(source)")
        }
        if operationCoordinator.isBusy {
            pendingRestoreSource = source
            do {
                try controller.requestEnableCancellation()
            } catch {
                logger.error("[State] restore cancellation marker could not be persisted: \(error.localizedDescription)")
            }
            logger.info("[State] restore queued with priority until the current display step returns, source=\(source)")
            return
        }
        switch state.mode {
        case .preparing, .confirmRequired, .headless, .fallback, .restoring, .error, .recoveryRequired:
            logger.info("[Perf] restore requestToSubmissionMs=\((DispatchTime.now().uptimeNanoseconds - requestedAt) / 1_000_000)")
            confirmDialogController.dismiss(reason: "restored by \(source)")
            runRestoreControllerOperation(name: "restore", source: source)
        case .normal:
            logger.info("[Perf] restore requestToSubmissionMs=\((DispatchTime.now().uptimeNanoseconds - requestedAt) / 1_000_000)")
            logger.info("[State] restore cleanup requested, source=\(source), current=Normal")
            runRestoreControllerOperation(name: "restore cleanup", source: source)
        }
    }

    func enableHeadlessFromSource(_ source: String) {
        guard !operationCoordinator.isBusy else {
            transientOperationTitle = nil
            updateTitle()
            logger.warn("[State] enable ignored, source=\(source), another controller operation is running")
            return
        }
        runControllerOperation(name: "enable", source: source, operation: { [controller, logger] in
            logger.info("[State] enable accepted, source=\(source)")
            try controller.enableHeadless()
        }, completion: { [weak self] result in
            guard let self else {
                return
            }
            guard self.pendingRestoreSource == nil else {
                self.logger.info("[State] enable completion UI skipped because Restore is pending.")
                return
            }
            switch result {
            case .success:
                self.confirmDialogRestoreSuppression.clear()
                let state = self.stateStore.load()
                self.showConfirmDialogIfNeeded(state: state, config: self.configManager.load().effectiveConfirmDialog)
            case .failure(let error):
                let safetyOutcome = self.stateStore.load().failureSafetyOutcome
                let presentation = AppEnableFailurePresentation.make(
                    outcome: safetyOutcome,
                    message: error.localizedDescription
                )
                if presentation.shouldMarkError {
                    self.markError(error)
                } else {
                    self.logger.error(error.localizedDescription)
                }
                self.showAlert(title: "Enable Headless Mode Failed", message: presentation.message)
            }
        })
    }

    func runRestoreControllerOperation(name: String, source: String) {
        transientOperationTitle = "Restoring Normal Mode..."
        updateTitle()
        let submitted = operationCoordinator.submit(
            name: name,
            source: source,
            operation: { [controller] in controller.restoreNormal() }
        ) { [weak self] result in
            guard let self else { return }
            self.replacementLossRestoreSubmitted = false
            self.transientOperationTitle = nil
            switch result {
            case .success(let restoreResult):
                let presentation = AppRestorePresentation.make(result: restoreResult)
                self.logger.info("[RestoreUI] \(presentation.message)")
                if !presentation.isSuccess {
                    self.showAlert(title: "Restore Needs Attention", message: presentation.message)
                }
            case .failure(let error):
                self.showAlert(title: "Restore Failed", message: error.localizedDescription)
            }
            self.confirmDialogRestoreSuppression.clear()
            if self.stateStore.load().mode == .normal {
                self.handleVerifiedNormalTransition(reason: "restore-completion")
            } else {
                self.refreshOperationalEvidence(source: .restoreCompletion)
            }
            if let pendingRestoreSource = self.pendingRestoreSource {
                self.pendingRestoreSource = nil
                self.handleRestoreRequested(source: pendingRestoreSource)
            }
        }
        if !submitted {
            replacementLossRestoreSubmitted = false
            confirmDialogRestoreSuppression.clear()
            transientOperationTitle = nil
            updateTitle()
            showAlert(title: "CodexHeadless Is Busy", message: "Another display operation is already running. Please wait for it to finish.")
        }
    }

    func runControllerOperation(
        name: String,
        source: String,
        operation: @escaping () throws -> Void,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        if name != "enable" {
            transientOperationTitle = "\(name.capitalized)..."
            updateTitle()
        }
        let submitted = operationCoordinator.submit(
            name: name,
            source: source,
            operation: operation
        ) { [weak self] result in
            guard let self else { return }
            self.transientOperationTitle = nil
            completion?(result)
            let finalMode = self.stateStore.load().mode
            if finalMode == .normal {
                self.handleVerifiedNormalTransition(reason: "\(name)-completion")
            } else {
                let source: OperationalEvidenceSource = name == "enable" ? .enableCompletion : (name == "confirm" ? .confirmCompletion : .periodicReconcile)
                self.refreshOperationalEvidence(source: source)
            }
            if let pendingRestoreSource = self.pendingRestoreSource {
                self.pendingRestoreSource = nil
                self.handleRestoreRequested(source: pendingRestoreSource)
            }
        }
        guard submitted else {
            transientOperationTitle = nil
            updateTitle()
            showAlert(title: "CodexHeadless Is Busy", message: "Another display operation is already running. Please wait for it to finish.")
            return
        }
    }

}
