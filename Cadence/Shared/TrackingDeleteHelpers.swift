import Foundation
import SwiftData

/// Deletion for `Goal` and `Habit`, matching the cascade rules `ListDeleteHelpers` uses.
///
/// Cross-platform, and deliberately so: it was `#if os(macOS)` in `macOS/Services/`, which left
/// iOS with no way to remove a goal or a habit at all. Nothing in here is AppKit-shaped.
///
/// Neither model had a delete path at all. The only code that removed either was
/// `ModelContext.deleteContext(_:)` and `PrivacyDataResetService`, so a goal or habit created by
/// mistake was permanent unless you deleted its entire Context or wiped the app — and a habit
/// created with no context and no goal (reachable: `CreateHabitSheet` with neither picked) could
/// not be removed by *any* means short of a full data reset. Marking something Done was the
/// de-facto delete, which is why the Goals page's default `.active` filter made it look like one.
extension ModelContext {
    /// Deletes a goal, its milestones, and the links that only exist to join it to something else.
    ///
    /// What is deliberately **not** deleted: the lists a `GoalListLink` points at, the habits that
    /// name this goal, and the tasks assigned to it. Those are the user's real work and outlive
    /// any goal that organised them — the relationships are severed, the objects survive. This
    /// mirrors `Goal.subGoals`' `.nullify` rule, and it is the same reasoning that keeps
    /// `TaskBundle.tasks` on nullify.
    ///
    /// **What it takes across contexts, and why `deleteContext` does not mirror it ([[T-1324]]).**
    /// The walk has no container filter, so a milestone filed under *Life* goes with its *Work*
    /// parent. `ModelContext.deleteContext` deletes `context.goals` and never walks `subGoals`, so
    /// that same milestone outlives a delete of *Work*, promoted to a top-level direction by
    /// `Goal.subGoals`' `.nullify` rule. The two readings differ on purpose, and [[T-1312]]'s
    /// argument — which settled the same disagreement one relationship over, for a goal's *tasks* —
    /// does not carry across to nesting for three reasons:
    ///
    /// * That leg was **redundant**: a task that was really the context's own already arrived
    ///   through its area, its project or its own `context`, so dropping it subtracted nothing but
    ///   somebody else's rows. `subGoals` is the only leg that reaches a milestone at all, so
    ///   filtering it would redefine the delete rather than remove a double count.
    /// * `AppTask.goal` is **free** of `AppTask.context`. `Goal.parentGoal` *derives* it:
    ///   `CadenceTrackingMutationSupport.saveGoal` writes `context ?? parentGoal?.context`, so a
    ///   milestone's context defaults to its parent's and a differing one is a deliberate override.
    /// * A severed task is still the object it was, in a list it already had. A severed milestone
    ///   is not: both Goals pages draw top-level goals with their milestones nested under them
    ///   (`GoalMissionGrouping.groups` on macOS, `topLevelGoals` + `milestones(of:)` on iOS) and
    ///   `GoalAssignmentRules.canOwnMilestones` keeps that two deep, so surviving means being
    ///   **promoted to a direction the user never created**.
    ///   Survival is not the conservative direction here.
    ///
    /// The repair T-1312's rule really does forbid is the other one — `context.goals` is already
    /// exact, so walking `subGoals` from a context cascade could only ever add another context's
    /// goals. Both halves are pinned, so the disagreement cannot go quiet again:
    /// `TrackingDeleteHelpersTests.deletingAGoalTakesAMilestoneWhoseOwnContextIsElsewhere` and
    /// `ListDeleteHelpersTests.deleteContextLeavesAMilestoneFiledElsewhereAliveAsATopLevelGoal`.
    ///
    /// **Throws when the store refuses the commit ([[T-1301]]).** This ended `try? save()`, and
    /// because the receiver is the store the commit was written with no qualifier at all — which is
    /// the one spelling `CadenceSaveCommitDisciplineTests`' needle could not read, so the existence
    /// half never saw a cascade delete of a whole goal subtree being swallowed here. A refused
    /// commit left every row in that subtree marked deleted in the app's single `ModelContext`,
    /// waiting for the next unrelated `save()` from any other screen to commit it — a delete the
    /// user was never told had failed, arriving later from somewhere that never mentioned goals.
    ///
    /// `commitDelete`'s undo is `rollback()`, which is the only undo available to a delete: the
    /// rows are already marked and there is no object to hand back. That is what earns
    /// `CadenceTrackingMutationSupport.goalDeleteFailureNotice`'s "Nothing was removed."
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    func deleteGoal(_ goal: Goal, commit: (ModelContext) throws -> Void = { try $0.save() }) throws {
        // Depth-first, so a milestone's own milestones go before it. The walk lives in
        // `GoalAssignmentRules` because the delete confirmation counts the same list — an alert
        // that counted direct children while this collected the subtree promised "1 milestone" and
        // deleted two.
        for doomed in GoalAssignmentRules.deletionCascade(from: goal) {
            for link in doomed.listLinks ?? [] {
                delete(link)
            }
            // Clearing the arrays below would nullify these through the inverse on its own, so
            // these two loops are belt-and-braces and no test can distinguish them. They stay
            // because this codebase does not trust inverse back-population to have happened by
            // the time anything reads it — three separate habit-toggle sites maintain
            // `Habit.completions` by hand for the same reason.
            for habit in doomed.habits ?? [] {
                habit.goal = nil
            }
            for task in doomed.tasks ?? [] {
                task.goal = nil
            }
            doomed.listLinks = []
            doomed.habits = []
            doomed.tasks = []
            doomed.parentGoal = nil
            doomed.subGoals = []
            delete(doomed)
        }

        processPendingChanges()
        try CadencePendingChangePersistence.commitDelete(in: self, commit: commit)
    }

    /// Deletes a habit and its completion history, and cancels its pending reminder.
    ///
    /// The reminder cancellation is not optional housekeeping: habit reminders repeat on
    /// time-of-day, so a pending request outliving its habit would fire a banner carrying the
    /// deleted habit's title every day until the next `scenePhase` reconcile. The context cascade
    /// in `ListDeleteHelpers` owes the same cancellation and **cannot spell it this way**: it
    /// commits nothing, so it has no `try` to sit below and it defers instead ([[T-1348]]). This
    /// comment used to name that cascade as the model for the line below, which was the reverse of
    /// the truth — it was the one site the rule below had never reached.
    ///
    /// **Throws, and the reminder is cancelled only below the commit ([[T-1301]]).** `deleteGoal`
    /// records why the swallow was invisible; this one had a second cost the goal side does not.
    /// The `Task { … cancel(habitIDs:) }` ran unconditionally after the swallowed save, so a
    /// refused commit cancelled the reminder for a habit that is still in the store and still on
    /// screen — silently, and not repaired until the next `scenePhase` reconcile. Moving it below
    /// the `try` makes the cancellation reachable only once the store has taken the delete.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    func deleteHabit(_ habit: Habit, commit: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let habitID = habit.id

        for completion in habit.completions ?? [] {
            completion.habit = nil
            delete(completion)
        }
        habit.completions = []
        habit.goal = nil
        habit.context = nil
        delete(habit)

        processPendingChanges()
        try CadencePendingChangePersistence.commitDelete(in: self, commit: commit)

        NotificationManager.cancelReminders(habitIDs: [habitID])
    }
}
