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

    /// Check `habit` in on `dateKey`, or clear it if it is already checked in, then save.
    ///
    /// Returns whether the habit reads as checked in afterwards. Throws whatever the save throws —
    /// the widget intent needs that failure, and the two in-app callers deliberately swallow it
    /// ([[T-322]]: a habit tick the user can retry with a second tap is not a save whose failure
    /// they can act on).
    @discardableResult
    static func toggle(
        _ habit: Habit,
        on dateKey: String,
        modelContext: ModelContext
    ) throws -> Bool {
        let existing = completions(for: habit, on: dateKey)
        let isCheckedIn: Bool
        if existing.isEmpty {
            let completion = HabitCompletion(date: dateKey, habit: habit)
            modelContext.insert(completion)
            habit.completions = (habit.completions ?? []) + [completion]
            isCheckedIn = true
        } else {
            // Clearing a day takes *every* row for it, including duplicates a second device
            // contributed — otherwise unchecking would leave the habit still reading as done.
            for completion in existing {
                detach(completion)
                modelContext.delete(completion)
            }
            isCheckedIn = false
        }
        try modelContext.save()
        return isCheckedIn
    }

    /// `[Type]?` to-many relationships are appended by assigning a new array, and severed the same
    /// way: leaving a deleted row in `habit.completions` is what makes a collapsed day still read
    /// as populated until the next fetch.
    private static func detach(_ completion: HabitCompletion) {
        guard let habit = completion.habit else { return }
        habit.completions = (habit.completions ?? []).filter { $0 !== completion }
    }
}
