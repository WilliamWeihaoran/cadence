import Foundation

/// Replaces the old `PursuitAssignmentRules`. Goals and habits used to *require* a parent
/// pursuit before they could be saved; now that pursuits are just top-level goals, a goal with
/// no parent is a legitimate direction rather than an unassigned orphan, so the only remaining
/// save requirement is a non-empty title.
enum GoalAssignmentRules {
    static func canSaveGoal(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canSaveHabit(title: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Top-level directions — goals that aren't a milestone of some other goal.
    static func topLevelGoals(from goals: [Goal]) -> [Goal] {
        goals.filter { $0.parentGoal == nil }
    }

    /// Milestones nested directly under `goal`.
    static func milestones(of goal: Goal) -> [Goal] {
        (goal.subGoals ?? []).sorted { $0.order < $1.order }
    }

    /// Whether `goal` may own milestones of its own.
    ///
    /// Goals nest exactly one level: a top-level goal is a direction and its sub-goals read as
    /// milestones. Nothing renders a third level — the goals list draws top-level rows plus their
    /// milestones, and the habit editor's goal picker offers the same two tiers — so a goal
    /// created under a milestone exists in the store and appears on no screen. The goal editor's
    /// `mustStayTopLevel` guard names this hazard for the parent-picker path; this is the same
    /// rule for the "new milestone" path.
    static func canOwnMilestones(_ goal: Goal) -> Bool {
        goal.parentGoal == nil
    }

    /// Every goal that goes when `goal` is deleted: the whole nested subtree, depth-first so a
    /// milestone's own milestones are ordered before it, with `goal` itself last.
    ///
    /// `ModelContext.deleteGoal` walks this list, and the delete confirmation counts it, so the
    /// alert cannot promise less than the delete performs. Counting `milestones(of:)` instead told
    /// a user with a goal → milestone → sub-milestone tree that "1 milestone" would go, and then
    /// deleted two. `visited` guards the cycle a corrupted `parentGoal` chain could produce,
    /// matching `GoalContributionResolver`.
    static func deletionCascade(from goal: Goal) -> [Goal] {
        var visited: Set<UUID> = []
        var ordered: [Goal] = []

        func collect(_ current: Goal) {
            guard visited.insert(current.id).inserted else { return }
            for child in current.subGoals ?? [] {
                collect(child)
            }
            ordered.append(current)
        }
        collect(goal)

        return ordered
    }

    /// How many *other* goals a delete of `goal` takes with it.
    static func nestedGoalCount(under goal: Goal) -> Int {
        max(0, deletionCascade(from: goal).count - 1)
    }

    /// Habits not tied to any goal. Still worth surfacing as a review queue, but no longer an
    /// invalid state the editors refuse to save.
    static func unlinkedHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { $0.goal == nil }
    }
}
