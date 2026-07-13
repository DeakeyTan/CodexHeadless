import Foundation

struct StandaloneJournalFinalizer {
    let stateStore: RuntimeStateStoring
    let journalStore: RecoveryJournalStoring
    let snapshotProvider: ManagedProcessSnapshotProviding

    func finalizeIfClean() throws {
        guard let journal = try journalStore.read(),
              journal.operationID.hasPrefix("standalone-") else { return }
        let keepAwakeActive = journal.keepAwakeHost != nil
            || journal.keepAwakeResource.map { $0.stage != .cleaned } == true
        let virtualActive = journal.virtualDisplayHost != nil
            || journal.virtualDisplayResource.map { $0.stage != .cleaned } == true
        let state = try stateStore.read()
        let runtimeActive = state.keepAwake || state.keepAwakeHost != nil || state.caffeinatePID != nil
            || state.virtualDisplayCreated || state.virtualDisplayHost != nil || state.virtualDisplayID != nil
        guard !keepAwakeActive, !virtualActive, !runtimeActive else { return }
        let snapshot = snapshotProvider.capture()
        guard snapshot.succeeded else {
            throw CodexHeadlessError.managedResource(
                message: "Standalone Journal finalization cannot verify managed processes: \(snapshot.error ?? "snapshot unavailable")."
            )
        }
        guard !snapshot.entries.contains(where: {
            $0.command.contains("internal-helper \(InternalHelperKind.keepAwakeHost.rawValue)")
                || $0.command.contains("internal-helper \(InternalHelperKind.virtualDisplayHost.rawValue)")
        }) else {
            throw CodexHeadlessError.managedResource(message: "Standalone managed helper is still observed; Recovery Journal was preserved.")
        }
        try journalStore.delete()
    }
}
