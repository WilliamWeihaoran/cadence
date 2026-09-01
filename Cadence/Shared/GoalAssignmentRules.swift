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

    /// Goals still in flight — the only ones the Goals screen draws a row for.
    ///
    /// **T-541.** The iOS Goals screen filters completed goals out of its list and counts what is
    /// left, so `status != .done` is not a presentation detail of one pane: it decides which goals
    /// exist as far as that screen is concerned. It lives here so the pane beside the list cannot
    /// answer the question differently from the list.
    static func activeGoals(from goals: [Goal]) -> [Goal] {
        goals.filter { $0.status != .done }
    }

    /// The rows the Goals list draws at the top level: genuine directions, plus any active
    /// milestone whose parent is completed — without the second half those milestones would have
    /// no row to appear under and drop off the screen.
    static func activeTopLevelGoals(from goals: [Goal]) -> [Goal] {
        let active = activeGoals(from: goals)
        let activeIDs = Set(active.map(\.id))
        return active.filter { goal in
            guard let parent = goal.parentGoal else { return true }
            return !activeIDs.contains(parent.id)
        }
    }

    /// The goal the Goals **detail** pane shows, given whatever the user last selected.
    ///
    /// **T-541 — every rung of this is filtered, and that is the whole point.** The detail pane
    /// used to resolve a selected id against the unfiltered collection and fall back to
    /// `goals.first`, so with every goal completed the chooser drew "No goals yet" while the pane
    /// beside it rendered a completed goal in full. It is the mirror image of [[T-514]]/[[T-534]]:
    /// there the list had no row for where you were, here the detail showed what the list had
    /// filtered away.
    ///
    /// **The deleted-out-from-under-you case this fallback exists for still holds.** A selected id
    /// that no longer resolves — the goal deleted on the Mac and the deletion arriving over
    /// CloudKit, or deleted from the compact list — still falls through to a default rather than to
    /// `nil`, which is what kept the iPad detail pane from reading as permanently unselectable.
    /// What it no longer does is resurrect a goal the list refuses to show.
    ///
    /// So this returns `nil` exactly when `activeGoals(from:)` is empty, which is exactly the count
    /// the list draws its empty panel on: both sides go empty together.
    static func selectedGoal(id: UUID?, from goals: [Goal]) -> Goal? {
        let active = activeGoals(from: goals)
        if let id, let match = active.first(where: { $0.id == id }) {
            return match
        }
        return activeTopLevelGoals(from: goals).first ?? active.first
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
