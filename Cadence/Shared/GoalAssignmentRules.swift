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

    /// Every goal nested beneath `goal` at **any** depth, flattened depth-first — the milestone
    /// list a two-tier Goals screen draws under a direction.
    ///
    /// **This is the rule that stops a deeper chain hiding a goal entirely ([[T-1337]]).** The
    /// editors refuse to build a goal → milestone → sub-milestone tree — `mustStayTopLevel(_:)`
    /// and `canOwnMilestones(_:)` below — but that only closed the door: a store written before
    /// [[T-1327]], or an archive import, still holds such trees, they sync through CloudKit, and
    /// `GoalContributionResolver.contributingTasks` recurses `subGoals` with no depth limit, so a
    /// sub-milestone's tasks move its grandparent's percentage. A percentage moved by a row no
    /// screen draws is the one outcome the user cannot account for, so the descendants are
    /// flattened into the tier that *is* drawn rather than left invisible or quietly discounted.
    ///
    /// macOS has read it this way since `926a67b` — `GoalMissionGrouping.nestedGoals` was this
    /// function, privately, on the one platform whose editor could build the tree. It moved here
    /// so the iOS list reads the same shape, for the reason `mustStayTopLevel(_:)` moved here:
    /// a rule kept on one of two platforms is not a rule.
    ///
    /// `visited` guards the cycle a corrupted `parentGoal` chain could produce, matching
    /// `deletionCascade(from:)` and `GoalContributionResolver`.
    static func nestedGoals(under goal: Goal) -> [Goal] {
        var visited: Set<UUID> = [goal.id]
        var result: [Goal] = []

        func walk(_ parent: Goal) {
            for child in milestones(of: parent) where !visited.contains(child.id) {
                visited.insert(child.id)
                result.append(child)
                walk(child)
            }
        }

        walk(goal)
        return result
    }

    /// `nestedGoals(under:)` filtered to the goals still in flight — the milestone rows the iOS
    /// Goals list draws under a direction.
    ///
    /// A completed goal partway down the chain does not hide what is under it: the filter is
    /// applied to the flattened list, not to the walk, so an active sub-milestone of a completed
    /// milestone still gets a row under the direction they both belong to.
    static func activeNestedGoals(under goal: Goal) -> [Goal] {
        activeGoals(from: nestedGoals(under: goal))
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

    /// The rows the Goals list draws at the top level: genuine directions, plus any active goal
    /// with no active **ancestor** — without the second half those milestones would have no row to
    /// appear under and drop off the screen.
    ///
    /// **Ancestor, not parent ([[T-1337]]).** The test was `parent` while the list drew exactly two
    /// tiers, and over a two-level tree the two readings are the same: a goal's only ancestor *is*
    /// its parent. They part over a goal → milestone → sub-milestone tree, which no editor will
    /// build any more but which stores written before [[T-1327]] hold. Asking about the parent
    /// alone promotes a sub-milestone whose parent is completed to a top-level row **while**
    /// `activeNestedGoals(under:)` already draws it under the direction it belongs to — the same
    /// goal twice. Asking about the whole chain says what the sentence above always meant: a goal
    /// is a top-level row exactly when nothing that is drawn will draw it.
    ///
    /// `visited` guards the cycle a corrupted `parentGoal` chain could produce; a goal inside one
    /// has itself as an ancestor, so a cycle of active goals still yields no top-level row and
    /// `selectedGoal(id:from:)`'s second rung is still the thing that answers.
    static func activeTopLevelGoals(from goals: [Goal]) -> [Goal] {
        let active = activeGoals(from: goals)
        let activeIDs = Set(active.map(\.id))
        return active.filter { goal in
            var visited: Set<UUID> = [goal.id]
            var ancestor = goal.parentGoal
            while let current = ancestor {
                if activeIDs.contains(current.id) { return false }
                guard visited.insert(current.id).inserted else { break }
                ancestor = current.parentGoal
            }
            return true
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
    /// milestones. That is the tree the screens are *drawn* as — two tiers, a direction and the
    /// milestones under it — and the habit editor's goal picker offers the same two, so a goal
    /// created under a milestone is a row the outline has no place for.
    ///
    /// **It is not, since [[T-1337]], a goal that appears nowhere.** `activeNestedGoals(under:)`
    /// flattens the whole subtree into the milestone tier on both platforms, because a tree that
    /// already exists still moves its direction's percentage and a percentage moved by an
    /// invisible row is the one outcome nothing can explain. The rule stands anyway, and the
    /// reason is now the weaker but sufficient one: a third level has no tier of its own to be
    /// drawn in, so creating one files work where its owner did not put it.
    ///
    /// The goal editor's `mustStayTopLevel` guard names this for the parent-picker path; this is
    /// the same rule for the "new milestone" path.
    static func canOwnMilestones(_ goal: Goal) -> Bool {
        goal.parentGoal == nil
    }

    /// Whether `goal` may **not** be given a parent, because it already owns milestones of its own.
    ///
    /// `canOwnMilestones` asked of a candidate *parent*; this is the same rule asked of the goal
    /// being **edited**. Nesting a goal that owns milestones pushes those milestones to a third
    /// level, which has no tier of its own on either Goals screen — see `canOwnMilestones(_:)` —
    /// so the goal that would be nested is the one that has to refuse, before the tree exists.
    /// `nil` is the create path, where there is no goal yet and nothing to keep top-level.
    ///
    /// **Both editors ask this one function now ([[T-1327]]).** It was `iOSGoalEditorSheet`'s own
    /// private computed property, so `CreateGoalSheet` offered a parent for a goal with milestones
    /// under it and `CadenceTrackingMutationSupport.saveGoal` took the selection — that function
    /// guards only the self-parenting *cycle*, never depth — which made the macOS editor the way a
    /// goal -> milestone -> sub-milestone tree came to exist at all. A rule enforced on one of two
    /// platforms is not a rule; it is a defect with a workaround.
    static func mustStayTopLevel(_ goal: Goal?) -> Bool {
        guard let goal else { return false }
        return goal.parentGoal == nil && !(goal.subGoals ?? []).isEmpty
    }

    /// What the parent picker says in place of itself when `mustStayTopLevel(_:)` is true.
    ///
    /// Beside the rule rather than in either editor, because it is the same sentence on both and
    /// was iOS's string before macOS needed it.
    static let mustStayTopLevelNotice = "This goal has milestones of its own, so it stays top-level."

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
