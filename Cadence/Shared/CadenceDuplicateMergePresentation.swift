import Foundation
import SwiftData

/// **[[T-6481]]: Settings > Data Safety > Merge Duplicates, on both platforms.**
///
/// The owner's decision (2026-10-26): after the RC, a USER-TRIGGERED merge where one device
/// decides, and no schema change. The automatic passes in `DataIntegrityRepairService` skip two
/// same-id tasks equal in every field, because two devices guessing would each delete the copy the
/// other kept; a person pressing this button on one device is the decider those passes lack.
///
/// Every word either card shows is here, and so is the one sequence both cards run (`run(in:)`),
/// so the Mac card (`SettingsDuplicateMergeCard`) and the phone card
/// (`iOSDuplicateMergeSettingsSection`) differ only in their card chrome — the way the export and
/// import cards already do.
enum CadenceDuplicateMergePresentation {
    static let title = "Merge Duplicates"

    static let description = """
        Folds any task, list or note that appears twice into one copy, keeping what only the other \
        copy held — its notes, tags, subtasks and focus time. Run it on one device; the result \
        syncs to the others. It cannot be undone, so export an archive first if you want a way back.
        """

    static let buttonTitle = "Merge Duplicates"
    static let confirmationTitle = "Merge duplicates on this device?"
    static let confirmationMessage = """
        Each extra copy is folded into the one Cadence keeps and then deleted, here and on your \
        other devices once they sync.
        """
    static let confirmButtonTitle = "Merge"
    static let cancelButtonTitle = "Cancel"

    /// Whether the merge may run now. A mirroring store whose first import of this launch has not
    /// finished could still be bringing down a subtask or focus session of a copy the merge would
    /// delete, and that child would arrive with its parent gone and nothing to re-point it by
    /// ([[T-6482]]) — so the button waits, exactly as the launch's own merges do.
    enum Readiness: Equatable {
        case ready
        case waitingForFirstSync
    }

    static func readiness(storeMirrorsToCloudKit: Bool, firstImportCompleted: Bool) -> Readiness {
        storeMirrorsToCloudKit && !firstImportCompleted ? .waitingForFirstSync : .ready
    }

    static let waitingForFirstSyncMessage = """
        iCloud has not finished bringing this device up to date yet. Try again once it has, so a \
        merge cannot delete a copy whose subtasks are still arriving.
        """

    static func outcomeMessage(mergedCount: Int) -> String {
        switch mergedCount {
        case ..<1: "No duplicates found. Nothing was changed."
        case 1: "Merged 1 duplicate."
        default: "Merged \(mergedCount) duplicates."
        }
    }

    static func failureMessage(_ reason: String) -> String {
        "Merge failed, nothing was changed: \(reason)"
    }

    /// The one sequence both cards run, returning the sentence the card shows.
    ///
    /// The two readiness inputs, left `nil`, are the live launch's answers; they are parameters so
    /// a test can drive both branches without a mirroring container.
    @MainActor
    static func run(
        in modelContext: ModelContext,
        storeMirrorsToCloudKit: Bool? = nil,
        firstImportCompleted: Bool? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> String {
        // Resolved here rather than as default arguments, which are evaluated outside the main
        // actor that owns both answers.
        guard readiness(
            storeMirrorsToCloudKit: storeMirrorsToCloudKit ?? PersistenceController.openedStoreMirrorsToCloudKit,
            firstImportCompleted: firstImportCompleted ?? CadenceSyncActivityLog.shared.hasObservedCompletedImport
        ) == .ready else {
            return waitingForFirstSyncMessage
        }
        do {
            let report = try DataIntegrityRepairService.mergeDuplicatesOnRequest(
                in: modelContext,
                removingForkedOccurrences: CadenceForkedOccurrenceRemover.removeAndCancelReminders,
                commit: commit
            )
            return outcomeMessage(mergedCount: report.duplicatesMerged)
        } catch {
            return failureMessage(error.localizedDescription)
        }
    }
}
