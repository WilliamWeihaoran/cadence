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
    func deleteGoal(_ goal: Goal) {
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
        try? save()
    }

    /// Deletes a habit and its completion history, and cancels its pending reminder.
    ///
    /// The reminder cancellation is not optional housekeeping: habit reminders repeat on
    /// time-of-day, so a pending request outliving its habit would fire a banner carrying the
    /// deleted habit's title every day until the next `scenePhase` reconcile. `ListDeleteHelpers`
    /// already does this for the context cascade; this is the same rule for a single habit.
    func deleteHabit(_ habit: Habit) {
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
        try? save()

        Task { await NotificationManager.shared.cancel(habitIDs: [habitID]) }
    }
}
