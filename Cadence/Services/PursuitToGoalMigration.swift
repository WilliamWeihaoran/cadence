import Foundation
import SwiftData

/// One-time migration folding the retired `Pursuit` model into `Goal`.
///
/// A pursuit becomes a top-level goal (`parentGoal == nil`) carrying its original kind,
/// and everything it owned is re-hung off that goal:
/// - each child `Goal` gets `parentGoal` set to the new goal, so it reads as a milestone of it
/// - each child `Habit` gets `goal` set to the new goal (unless it already points at a goal,
///   which is a stronger, more specific link and is left alone)
///
/// `GoalContributionResolver` already recurses through `subGoals`, so progress rolls up to the
/// migrated goal with no extra work.
///
/// Guarded by a `UserDefaults` flag, but **the flag is a fast path rather than the decision**: it
/// only skips the pass when the store also has no `Pursuit` rows left. It is deliberately
/// idempotent and non-destructive on failure: pursuits are only deleted after their children have
/// been successfully re-pointed and the context has saved.
///
/// ## Removal checklist (safe once every synced device has launched this build)
/// 1. Delete `Cadence/Models/Pursuit.swift`
/// 2. Delete `Goal.pursuit`, `Habit.pursuit`, `Context.pursuits`
/// 3. Remove `Pursuit.self` from `CadenceSchema.schema`
/// 4. Remove `Pursuit.self` from `PrivacyDataResetService` and `ListDeleteHelpers`
/// 5. Delete this file and its call site in `PersistenceController`
nonisolated enum PursuitToGoalMigration {
    /// Bumped if the migration ever needs to run again for a corrected pass.
    private static let completionKey = "pursuitToGoalMigration.v1.completed"

    /// Runs the migration unless the store demonstrably has nothing left to migrate.
    ///
    /// **Content-aware, because the flag alone strands rows.** `PersistenceController.init`
    /// applies a pending restore (`StoreBackupManager.performPendingRestoreIfNeeded`) *before* it
    /// opens the container and calls `performStartupMaintenance`, so the store this sees may be a
    /// backup that predates the migration. On a device that already migrated, the flag is set and
    /// a flag-only guard skips the pass forever: the restored `Pursuit` rows are never folded into
    /// `Goal`, and no surface shows them. The privacy reset clears the restore flags and not this
    /// one, so there is no path back either. The flag is kept only to make the common launch a
    /// `fetchLimit: 1` probe rather than a full pass. T-393.
    ///
    /// **It answers instead of returning `Void`** ([[T-1402]]). `migrate` already computed a
    /// clean/failed `Bool` and this discarded it, so [[T-1366]]'s launch instrument had nothing at
    /// all to classify and filed the pass as `indeterminate`. The answer is widened rather than
    /// merely forwarded, because the `Bool` could not separate a migration that folded rows from
    /// one that found none — and the flag-only fast path below could not separate either of those
    /// from a probe fetch that threw.
    @discardableResult
    static func runIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = CadenceDefaults.store
    ) -> CadenceMaintenancePassOutcome {
        if defaults.bool(forKey: completionKey) {
            switch hasSurvivingPursuits(in: modelContext) {
            case .some(false):
                return .nothingToDo
            case .none:
                // The probe fetch threw. Pre-T-1402 this returned as if the store were clean; it
                // is a store nobody could read, and a launch that says so can be believed the next
                // time it says the migration had nothing left to do.
                return .couldNotRead
            case .some(true):
                break
            }
        }
        let outcome = migrate(modelContext: modelContext)
        // Only latch the flag on a clean run. If the save threw we want to retry next launch
        // rather than silently strand pursuits that were never converted.
        if outcome != .couldNotRead { defaults.set(true, forKey: completionKey) }
        return outcome
    }

    /// Whether any `Pursuit` row is still in the store. One row is enough to decide, so this asks
    /// for one rather than fetching the lot on every launch.
    ///
    /// **`nil` is a fetch that threw**, kept apart from `false` since [[T-1402]]. It used to answer
    /// `false` for both — the pre-T-393 behaviour for a set flag — which skipped the pass on a
    /// store nobody could read and reported that skip as a launch with nothing to migrate. The
    /// caller still skips; what changed is that it no longer calls the skip clean. A store that
    /// cannot be read is still not one to start deleting rows in.
    private static func hasSurvivingPursuits(in modelContext: ModelContext) -> Bool? {
        var descriptor = FetchDescriptor<Pursuit>()
        descriptor.fetchLimit = 1
        guard let surviving = try? modelContext.fetch(descriptor) else { return nil }
        return !surviving.isEmpty
    }

    /// What the pass did: folded pursuits into goals, found none to fold, or could not finish.
    ///
    /// `couldNotRead` covers the fetch and **both** saves — [[T-1402]] kept them one answer rather
    /// than three, because every one of them leaves the same state behind: pursuits still in the
    /// store, the completion flag unset, and a retry owed on the next launch.
    @discardableResult
    static func migrate(modelContext: ModelContext) -> CadenceMaintenancePassOutcome {
        let pursuits: [Pursuit]
        do {
            pursuits = try modelContext.fetch(FetchDescriptor<Pursuit>())
        } catch {
            return .couldNotRead
        }
        guard !pursuits.isEmpty else { return .nothingToDo }

        for pursuit in pursuits {
            let goal = Goal(title: pursuit.title, context: pursuit.context)
            goal.desc = pursuit.desc
            goal.icon = pursuit.icon
            goal.colorHex = pursuit.colorHex
            goal.kind = pursuit.kind
            goal.status = pursuit.status
            goal.order = pursuit.order
            goal.createdAt = pursuit.createdAt
            // A pursuit had no dates; leaving start/end empty keeps it rendering as an
            // undated direction on the goal timeline rather than a zero-length bar.
            modelContext.insert(goal)

            for child in pursuit.goals ?? [] {
                // Don't reparent a goal that already sits under another goal — that nesting
                // was set explicitly and is more specific than the pursuit grouping.
                if child.parentGoal == nil {
                    child.parentGoal = goal
                }
                child.pursuit = nil
            }

            for habit in pursuit.habits ?? [] {
                if habit.goal == nil {
                    habit.goal = goal
                }
                habit.pursuit = nil
            }
        }

        do {
            // Save the re-pointed children before deleting anything, so a failure here leaves
            // the pursuits intact for a retry instead of orphaning their contents.
            try modelContext.save()
        } catch {
            return .couldNotRead
        }

        for pursuit in pursuits {
            modelContext.delete(pursuit)
        }

        do {
            try modelContext.save()
        } catch {
            // Children are already migrated and the flag stays unset, so the next launch
            // re-runs and finds nothing left to convert beyond the undeleted pursuits.
            return .couldNotRead
        }
        return .changed
    }
}
