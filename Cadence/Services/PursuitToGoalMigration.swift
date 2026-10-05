import Foundation
import SwiftData

/// The retired one-time migration that folded the retired `Pursuit` model into `Goal`.
///
/// **It no longer writes anything, and that is the whole of [[T-2077]] on this file.** Until this
/// build `migrate` constructed a `Goal` per surviving `Pursuit`, inserted it, re-hung that
/// pursuit's child goals and habits off it and saved — **on launch**, from
/// `PersistenceController.performStartupMaintenance`, with no user action at all. The owner
/// retired goals and habits at the depth "remove the UI and stop writing, keep the schema", so a
/// launch-time pass that mints `Goal` records would have been the one path still making new ones,
/// and it would have made them where nothing can show them.
///
/// **When it could still have fired, which is why neutering it was not optional.** The
/// `UserDefaults` completion flag was never the decision — [[T-393]] made the pass content-aware
/// precisely because `PersistenceController.init` applies a pending restore
/// (`StoreBackupManager.performPendingRestoreIfNeeded`) *before* it opens the container, so a
/// store that already migrated can be replaced by a backup that predates the migration and still
/// carry `Pursuit` rows. With the flag set, the pass re-probed for them and re-ran. So "the owner
/// migrated long ago" was never enough: any restore of a pre-merge backup, on any synced device,
/// re-armed it.
///
/// **What happens to a surviving `Pursuit` row now: nothing, which is the same thing that happens
/// to a `Goal` row.** Both models stay in `CadenceSchema`, both keep their CloudKit record types,
/// and neither is read by a live surface any more. Folding a pursuit into a goal would move a row
/// nobody can see into another row nobody can see, so there is genuinely nothing to do — the pass
/// answers `.nothingToDo` rather than being deleted outright, so [[T-1366]]'s launch instrument
/// keeps the `.pursuitMigration` stage it classifies and `CadenceFirstLaunchEmptyStoreTests`'
/// derived pass set is unchanged.
///
/// Nothing here deletes a row either. The owner's existing pursuits, goals, habits and habit
/// completions are left exactly as they are, which is what makes the retirement reversible.
nonisolated enum PursuitToGoalMigration {
    /// Always `.nothingToDo`. See the type's note: there is no longer a destination to fold a
    /// pursuit into that any surface reads, so the pass has no work rather than skipped work.
    ///
    /// It keeps `modelContext` and `defaults` so the launch call site and its tests do not move,
    /// and deliberately touches neither: a fetch would be a read with no consumer, and writing the
    /// completion flag would record a migration that did not happen.
    @discardableResult
    static func runIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = CadenceDefaults.store
    ) -> CadenceMaintenancePassOutcome {
        _ = modelContext
        _ = defaults
        return .nothingToDo
    }
}
