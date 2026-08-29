import Foundation
import SwiftData

enum CadenceTrackingMutationSupport {

    /// Shown when a goal the user asked for could not be committed (T-322).
    ///
    /// One sentence for both halves of `saveGoal` — the create that inserts and the edit that
    /// writes fields — because the *button* is one button and the user does not experience "new"
    /// and "changed" as two operations. It carries no "Nothing was changed." clause for the same
    /// reason the rest of the create family carries none
    /// (`TaskCreationService.saveFailureNotice`, `CadenceTaskMutationSupport.bundleSaveFailureNotice`):
    /// the sheet is still open over the user's own typed values, which live in the editor's
    /// `@State` and were never the store's to lose.
    static let goalSaveFailureNotice = "Couldn't save this goal."

    /// `habitSaveFailureNotice` to `saveHabit` as `goalSaveFailureNotice` is to `saveGoal`.
    ///
    /// Two sentences rather than one shared "Couldn't save this." because every failure notice in
    /// this repo names its own object — four screens, four nouns, one shape, per
    /// `CadenceTaskMutationSupport.deleteFailureNotice`.
    static let habitSaveFailureNotice = "Couldn't save this habit."

    /// The fields `saveGoal` writes, captured before it writes them.
    ///
    /// Every field below is one `saveGoal` assigns; `order` is not here because only the *create*
    /// path sets it, and that path undoes itself by deleting the object rather than by restoring
    /// fields. Adding a twelfth assignment to `saveGoal` without adding it here would make the undo
    /// silently partial, which is why the two lists sit ten lines apart.
    private struct GoalFieldSnapshot {
        let title: String
        let desc: String
        let startDate: String
        let endDate: String
        let progressType: GoalProgressType
        let targetHours: Double
        let icon: String
        let colorHex: String
        let kind: GoalKind
        let status: GoalStatus
        let context: Context?
        let parentGoal: Goal?

        init(_ goal: Goal) {
            title = goal.title
            desc = goal.desc
            startDate = goal.startDate
            endDate = goal.endDate
            progressType = goal.progressType
            targetHours = goal.targetHours
            icon = goal.icon
            colorHex = goal.colorHex
            kind = goal.kind
            status = goal.status
            context = goal.context
            parentGoal = goal.parentGoal
        }

        func restore(to goal: Goal) {
            goal.title = title
            goal.desc = desc
            goal.startDate = startDate
            goal.endDate = endDate
            goal.progressType = progressType
            goal.targetHours = targetHours
            goal.icon = icon
            goal.colorHex = colorHex
            goal.kind = kind
            goal.status = status
            goal.context = context
            goal.parentGoal = parentGoal
        }
    }

    /// `GoalFieldSnapshot`, for `saveHabit`.
    private struct HabitFieldSnapshot {
        let title: String
        let icon: String
        let colorHex: String
        let frequencyType: HabitFrequency
        let frequencyDays: [Int]
        let targetCount: Int
        let context: Context?
        let goal: Goal?

        init(_ habit: Habit) {
            title = habit.title
            icon = habit.icon
            colorHex = habit.colorHex
            frequencyType = habit.frequencyType
            frequencyDays = habit.frequencyDays
            targetCount = habit.targetCount
            context = habit.context
            goal = habit.goal
        }

        func restore(to habit: Habit) {
            habit.title = title
            habit.icon = icon
            habit.colorHex = colorHex
            habit.frequencyType = frequencyType
            habit.frequencyDays = frequencyDays
            habit.targetCount = targetCount
            habit.context = context
            habit.goal = goal
        }
    }

    /// `parentGoal == nil` creates a top-level direction (what used to be a pursuit);
    /// passing a parent nests this goal as a milestone of it.
    ///
    /// **Throws when the store refuses the write (T-322).** This was `try? modelContext.save()`
    /// followed by `return resolved`, and all three of its callers — `CreateGoalSheet` on macOS,
    /// `iOSGoalEditorSheet`, and the habit sibling below — read a non-`nil` answer as success and
    /// `dismiss()`. A refused save therefore closed the editor over a goal the store had never
    /// taken. Same defect and same fix as `insertBundle(title:…)` (T-471) and
    /// `insertScheduledTask` (T-470).
    ///
    /// `nil` still means only what it always meant: **the title was empty**, so there was nothing to
    /// make a goal out of. Keeping that answer distinct from a throw is the separation T-470 drew —
    /// "you typed nothing" is not a failure to report, and a caller that conflates the two shows an
    /// error for a blank field or swallows a refused store, depending which way it guesses.
    ///
    /// The two paths undo differently because they are different pending changes, which is the whole
    /// of `CadencePendingChangePersistence`'s reason for existing: a create un-inserts, an edit puts
    /// the fields back. Neither may be left pending — this app has one `ModelContext`, and an
    /// uncommitted change sitting in it is committed by the next unrelated `save()` or discarded by
    /// the next unrelated `rollback()`, so "swallow it and hope" is not a third outcome, it is a
    /// coin flip on someone else's code path.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func saveGoal(
        _ goal: Goal?,
        title: String,
        desc: String,
        startDate: String,
        endDate: String,
        progressType: GoalProgressType,
        targetHours: Double,
        icon: String,
        colorHex: String,
        kind: GoalKind,
        status: GoalStatus,
        context: Context?,
        parentGoal: Goal?,
        allGoals: [Goal],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Goal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved = goal ?? Goal(title: trimmed)
        let snapshot = goal.map { GoalFieldSnapshot($0) }
        resolved.title = trimmed
        resolved.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        resolved.startDate = startDate
        resolved.endDate = endDate < startDate ? startDate : endDate
        resolved.progressType = progressType
        resolved.targetHours = max(0, targetHours)
        resolved.icon = icon
        resolved.colorHex = colorHex
        resolved.kind = kind
        resolved.status = status
        resolved.context = context ?? parentGoal?.context
        // Guard against a goal becoming its own parent, which would make the subGoals
        // recursion in GoalContributionResolver walk a cycle.
        resolved.parentGoal = (parentGoal?.id == resolved.id) ? nil : parentGoal

        if goal == nil {
            resolved.order = nextOrder(in: allGoals)
            modelContext.insert(resolved)
            try CadencePendingChangePersistence.commitInsert(
                of: resolved,
                in: modelContext,
                commit: commit
            )
        } else {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                snapshot?.restore(to: resolved)
            }
        }
        return resolved
    }

    /// `saveGoal`'s sibling, throwing for the same reason and undoing the same two ways (T-322).
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func saveHabit(
        _ habit: Habit?,
        title: String,
        icon: String,
        colorHex: String,
        frequencyType: HabitFrequency,
        frequencyDays: [Int],
        targetCount: Int,
        context: Context?,
        goal: Goal?,
        allHabits: [Habit],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Habit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved = habit ?? Habit(title: trimmed)
        let snapshot = habit.map { HabitFieldSnapshot($0) }
        resolved.title = trimmed
        resolved.icon = icon
        resolved.colorHex = colorHex
        resolved.frequencyType = frequencyType
        resolved.frequencyDays = frequencyDays
        resolved.targetCount = max(1, targetCount)
        resolved.context = context ?? goal?.context
        resolved.goal = goal

        if habit == nil {
            resolved.order = nextOrder(in: allHabits)
            modelContext.insert(resolved)
            try CadencePendingChangePersistence.commitInsert(
                of: resolved,
                in: modelContext,
                commit: commit
            )
        } else {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                snapshot?.restore(to: resolved)
            }
        }
        return resolved
    }

    private static func nextOrder<T>(in items: [T], order: (T) -> Int) -> Int {
        CadenceOrderAllocation.nextOrder(after: items, order: order)
    }

    private static func nextOrder(in goals: [Goal]) -> Int {
        nextOrder(in: goals, order: \.order)
    }

    private static func nextOrder(in habits: [Habit]) -> Int {
        nextOrder(in: habits, order: \.order)
    }
}
