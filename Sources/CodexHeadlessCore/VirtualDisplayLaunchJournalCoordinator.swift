import Foundation

final class VirtualDisplayLaunchJournalCoordinator {
    private let journalStore: RecoveryJournalStoring

    init(journalStore: RecoveryJournalStoring) {
        self.journalStore = journalStore
    }

    func persistProvisionalHost(
        _ host: VirtualDisplayHostRecord,
        ownership: ManagedProcessOwnershipRecord
    ) throws {
        try journalStore.update { journal in
            journal.virtualDisplayHost = host
            journal.virtualDisplayResource?.ownership = ownership
        }
    }

    func persistReadyDisplay(
        _ displayID: UInt32,
        host: VirtualDisplayHostRecord
    ) throws {
        try journalStore.update { journal in
            journal.virtualDisplayHost = host
            journal.replacementDisplayID = displayID
            journal.virtualDisplayResource?.displayID = displayID
            journal.virtualDisplayResource?.stage = .observed
            journal.stage = .virtualDisplayStarted
        }
    }
}
