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
    static func runIfNeeded(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        if defaults.bool(forKey: completionKey), !hasSurvivingPursuits(in: modelContext) {
            return
        }
        let migrated = migrate(modelContext: modelContext)
        // Only latch the flag on a clean run. If the save threw we want to retry next launch
        // rather than silently strand pursuits that were never converted.
        if migrated { defaults.set(true, forKey: completionKey) }
    }

    /// Whether any `Pursuit` row is still in the store. One row is enough to decide, so this asks
    /// for one rather than fetching the lot on every launch.
    ///
    /// A throwing fetch answers `false`: that is the pre-T-393 behaviour for a set flag, and a
    /// store that cannot be read is not one to start deleting rows in.
    private static func hasSurvivingPursuits(in modelContext: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Pursuit>()
        descriptor.fetchLimit = 1
        guard let surviving = try? modelContext.fetch(descriptor) else { return false }
        return !surviving.isEmpty
    }

    /// Returns `true` when the pass completed cleanly (including the "nothing to do" case).
    @discardableResult
    static func migrate(modelContext: ModelContext) -> Bool {
        let pursuits: [Pursuit]
        do {
            pursuits = try modelContext.fetch(FetchDescriptor<Pursuit>())
        } catch {
            return false
        }
        guard !pursuits.isEmpty else { return true }

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
            return false
        }

        for pursuit in pursuits {
            modelContext.delete(pursuit)
        }

        do {
            try modelContext.save()
        } catch {
            // Children are already migrated and the flag stays unset, so the next launch
            // re-runs and finds nothing left to convert beyond the undeleted pursuits.
            return false
        }
        return true
    }
}
