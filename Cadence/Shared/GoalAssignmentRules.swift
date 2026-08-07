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

    /// Habits not tied to any goal. Still worth surfacing as a review queue, but no longer an
    /// invalid state the editors refuse to save.
    static func unlinkedHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { $0.goal == nil }
    }
}
