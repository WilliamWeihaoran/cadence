import Foundation
import SwiftData

/// The one place a habit check-in is written, and the one implementation of "collapse a habit-day
/// that has more than one row".
///
/// Four files used to open-code the same insert-if-none-exists toggle — `HabitsView`,
/// `CadenceHabitSupport` in `CadenceFocusPlanningSupport`, `ToggleHabitCompletionIntent`, and the
/// iOS habits list through the second of those. Each independently asked "is there a completion
/// for this date?" and inserted if not, which is the [[T-374]] shape: a rule that only holds while
/// every copy of it agrees. `CadenceHabitCompletionDuplicateTests` scans `Cadence/` and fails if
/// any file other than this one constructs a `HabitCompletion`.
///
/// **One writer cannot make a habit-day unique on its own.** The duplicate [[T-359]] is about is
/// minted on a *second device*, and a CloudKit-backed store has no uniqueness constraint to refuse
/// it, so the guard is three things together: one writer (here), a read that collapses duplicates
/// (`HabitCompletion.collapsedCount(of:)`, used by `Habit.completionCountsByDate()`), and a repair
/// that removes them (`DataIntegrityRepairService`, which collapses through this type rather than
/// spelling the rule a second time).
nonisolated enum CadenceHabitCompletionStore {

    /// Every row this habit holds for `dateKey`. Normally zero or one; more than one means two
    /// devices recorded the same check-in.
    ///
    /// Private: "is this habit checked in on this day" is already `Habit.isDone(on:)`, and a
    /// second spelling of it here would be the near-copy this type exists to remove.
    private static func completions(for habit: Habit, on dateKey: String) -> [HabitCompletion] {
        (habit.completions ?? []).filter { $0.date == dateKey }
    }

    /// Reduce a set of rows that all describe **one habit-day** to a single row, keeping
    /// `HabitCompletion.canonicalRow(among:)` and giving it the day's `collapsedCount`. Returns
    /// the number of rows removed.
    ///
    /// Does not save; the caller decides when the context is written.
    ///
    /// Rows are compared by identity, not by `id`. Two rows carrying the same `id` is exactly the
    /// state a bad merge or a half-applied restore leaves behind, and filtering the survivor's own
    /// `id` out of the relationship would then take the survivor with it.
    @discardableResult
    static func collapseDuplicates(_ rows: [HabitCompletion], modelContext: ModelContext) -> Int {
        guard rows.count > 1, let survivor = HabitCompletion.canonicalRow(among: rows) else { return 0 }

        let collapsed = HabitCompletion.collapsedCount(of: rows)
        if survivor.count != collapsed {
            survivor.count = collapsed
        }

        var removed = 0
        for row in rows where row !== survivor {
            detach(row)
            modelContext.delete(row)
            removed += 1
        }
        return removed
    }

    /// Check `habit` in on `dateKey`, or clear it if it is already checked in, then commit.
    ///
    /// Returns whether the habit reads as checked in afterwards. Throws whatever the commit throws.
    ///
    /// **The throw and the undo are two different questions, and [[T-322]] only settled the first.**
    /// The widget intent reports the failure and the two in-app callers deliberately swallow it —
    /// "a habit tick the user can retry with a second tap is not a save whose failure they can act
    /// on" — and that stays. What did not follow from it, and was the defect [[T-1295]] names, is
    /// that a refused commit used to leave the change *pending*. This app has one `ModelContext`,
    /// so an uncommitted insert waits there for the next unrelated `save()` anywhere to take it,
    /// with `habit.completions` already holding the row and the day already drawn checked in; the
    /// uncheck direction is the same shape with the rows pending-*deleted*. Swallowing an error is
    /// only defensible when there is nothing left to swallow.
    ///
    /// So both directions commit through `CadencePendingChangePersistence` and both put
    /// `habit.completions` back themselves:
    ///
    /// - **Insert.** `commitInsert` un-inserts the row it was handed, and that undo does not reach
    ///   the parent's array — the same measured gap `iOSTaskDetailSheet.addSubtask` captures
    ///   `task.subtasks` for. Leaving the deleted row in `habit.completions` is exactly what
    ///   `detach` below exists to prevent: the day still reads as done off a row the store refused.
    /// - **Delete.** `commitDelete` rolls the context back, which is the only way to un-delete
    ///   rows, and the captured array is re-applied for the reason [[T-1280]]'s survey kept the one
    ///   in `deleteSubtask`: it repairs *this* habit's own array without depending on what the
    ///   toolchain does with a rolled-back relationship. Through Xcode 26 `rollback()` did not
    ///   restore an already-materialised reference before a refetch; Xcode 27 does ([[T-1279]]).
    ///   Re-applying the array is correct on both and a no-op on the one that already did it.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter for
    ///   the reason `CadencePendingChangePersistence.commitInsert(of:in:commit:)` gives — a
    ///   `save()` that throws cannot be provoked out of an in-memory container, so without it the
    ///   undo path above is one no test can reach.
    @discardableResult
    static func toggle(
        _ habit: Habit,
        on dateKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Bool {
        let existing = completions(for: habit, on: dateKey)
        let restored = habit.completions ?? []

        if existing.isEmpty {
            let completion = HabitCompletion(date: dateKey, habit: habit)
            modelContext.insert(completion)
            habit.completions = restored + [completion]
            do {
                try CadencePendingChangePersistence.commitInsert(
                    of: completion,
                    in: modelContext,
                    commit: commit
                )
            } catch {
                habit.completions = restored
                throw error
            }
            return true
        }

        // Clearing a day takes *every* row for it, including duplicates a second device
        // contributed — otherwise unchecking would leave the habit still reading as done.
        for completion in existing {
            detach(completion)
            modelContext.delete(completion)
        }
        do {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)
        } catch {
            habit.completions = restored
            throw error
        }
        return false
    }

    /// `[Type]?` to-many relationships are appended by assigning a new array, and severed the same
    /// way: leaving a deleted row in `habit.completions` is what makes a collapsed day still read
    /// as populated until the next fetch.
    private static func detach(_ completion: HabitCompletion) {
        guard let habit = completion.habit else { return }
        habit.completions = (habit.completions ?? []).filter { $0 !== completion }
    }
}
