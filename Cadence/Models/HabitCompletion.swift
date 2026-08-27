import SwiftData
import Foundation

@Model final class HabitCompletion {
    var id: UUID = UUID()
    var date: String = ""   // YYYY-MM-DD
    var count: Int = 1
    var createdAt: Date = Date()

    var habit: Habit? = nil

    init(date: String, habit: Habit? = nil) {
        self.date = date
        self.habit = habit
    }
}

// MARK: - One habit-day, several rows (T-359)

extension HabitCompletion {
    /// What a habit-day is worth when more than one row claims it: **the largest single row, not
    /// the sum of them.**
    ///
    /// There is no uniqueness constraint available on a CloudKit-backed store, so two devices that
    /// check the same habit in on the same day mint two rows with two `id`s and both survive the
    /// merge. `Habit.completionCountsByDate()` used to add them, which is how one real check-in
    /// came to satisfy a `targetCount` of 2 or a `.timesPerWeek` target (T-359).
    ///
    /// **`max` rather than `sum`, because of what the app actually writes.** Every check-in path
    /// goes through `CadenceHabitCompletionStore.toggle`, and it is binary: if the day already has
    /// a row it deletes the day's rows, otherwise it inserts exactly one row at the default
    /// `count` of 1. Nothing in the app increments an existing row, so a second row for one
    /// habit-day is never a second deliberate increment — the second tap is an *un*-check. `sum`
    /// therefore only ever models an interaction the product does not have, and it prices that
    /// fiction at mis-scoring the one it does. `max` reads the duplicate as what it is: the same
    /// check-in recorded twice.
    ///
    /// A genuine multi-count day is unharmed, because it lives in one row's `count`: `max` over a
    /// single row of 3 is still 3. Only a day whose quantity was *split* across rows reads lower,
    /// and no writer produces that split.
    ///
    /// Negative counts clamp to 0, matching the old summing behaviour.
    static func collapsedCount<Rows: Sequence>(of rows: Rows) -> Int where Rows.Element == HabitCompletion {
        rows.reduce(0) { largest, row in max(largest, max(0, row.count)) }
    }

    /// The row that survives when a habit-day's duplicates are collapsed, or `nil` for no rows.
    ///
    /// The ordering is **total and device-independent** on purpose. Repair runs separately on
    /// every device against its own copy of the same rows; if two devices picked different
    /// survivors they would delete each other's keeper and the day could end up with none. Highest
    /// `count` first (so the survivor already carries `collapsedCount`), then oldest `createdAt`,
    /// then `id` — the same "end on the identity the app already has" tie-break `TaskOrdering`
    /// uses.
    static func canonicalRow<Rows: Sequence>(among rows: Rows) -> HabitCompletion? where Rows.Element == HabitCompletion {
        rows.min(by: survivorPrecedes)
    }

    private static func survivorPrecedes(_ lhs: HabitCompletion, _ rhs: HabitCompletion) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
