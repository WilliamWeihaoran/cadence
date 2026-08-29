import Foundation
import SwiftData

nonisolated enum CadenceMilestoneWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

nonisolated struct CadenceMilestoneWidgetGoal: Identifiable, Hashable {
    let id: UUID
    let title: String
    let colorHex: String
    let percentLabel: String
    let progress: Double
    let overdueTaskCount: Int
    let nextActionTitle: String?
    let linkedHabitCount: Int
    let dueTodayLabel: String
    /// `yyyy-MM-dd` due date of the next action, empty when it has none. Defaulted so goal
    /// literals that only care about the title stay source-compatible.
    var nextActionDueDate: String = ""
}

nonisolated struct CadenceMilestoneWidgetSnapshot: Hashable {
    let date: Date
    let state: CadenceMilestoneWidgetSnapshotState
    let statusMessage: String?
    let totalGoalCount: Int
    let totalOverdueTaskCount: Int
    let visibleGoals: [CadenceMilestoneWidgetGoal]

    var goalsURL: URL {
        CadenceDeepLink.goals.url
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

/// A pool goal with the two summaries this widget both ranks and renders it by, resolved once.
///
/// See `CadenceMilestoneWidgetSupport.snapshot(from:now:limit:)` — this type exists so the ranking
/// pass can hand its work to the rendering pass instead of dropping it (T-313).
nonisolated struct CadenceMilestoneWidgetGoalDecoration {
    let goal: Goal
    let contribution: GoalContributionSummary
    let momentum: GoalHabitMomentumSummary
}

nonisolated enum CadenceMilestoneWidgetSupport {
    static func snapshot(
        modelContext: ModelContext,
        limit: Int
    ) throws -> CadenceMilestoneWidgetSnapshot {
        let descriptor = FetchDescriptor<Goal>()
        let goals = try modelContext.fetch(descriptor)
        return snapshot(from: goals, now: Date(), limit: limit)
    }

    /// **T-313: every goal is resolved exactly once here.**
    ///
    /// This used to walk the same trees three times over. `prioritizedGoals` decorated the pool
    /// with a contribution summary and a habit-momentum summary, ranked by them, and then threw
    /// both away at `.map(\.goal)`; `widgetGoal` recomputed both for every goal the widget draws;
    /// and the overdue rollup called `GoalContributionResolver.overdueTasks` once more for every
    /// active goal. Each of those recurses sub-goals, linked lists, tasks and habits, so on a large
    /// store the timeline could approach WidgetKit's execution budget — and a widget that overruns
    /// it renders *nothing*, which is a worse failure than any number this file computes.
    ///
    /// One contribution walk per active goal and one momentum walk per pool goal now, shared by
    /// the ranking, the rendering and the rollup.
    static func snapshot(
        from goals: [Goal],
        now: Date = Date(),
        limit: Int
    ) -> CadenceMilestoneWidgetSnapshot {
        let contributions = activeContributions(from: goals, now: now)
        let pool = ranked(contributions, now: now)
        let visibleGoals = pool.prefix(max(limit, 0)).map(widgetGoal)

        return CadenceMilestoneWidgetSnapshot(
            date: now,
            state: pool.isEmpty ? .empty : .ready,
            statusMessage: nil,
            // The header's number, and it counts the same things the header names: "Milestones 7"
            // over a list the widget draws seven of. Before T-355 it counted every active goal
            // including the directions the list does not show.
            totalGoalCount: pool.count,
            // Union, not sum, and over **every** active goal rather than over the pool. Union
            // because a direction's contributing tasks already include its milestones', so adding
            // per-goal counts reports the same overdue task once per level it hangs under. Over
            // every active goal because a direction that steps out of the pool can still own
            // overdue tasks directly, and this badge is the app's overdue total, not the visible
            // rows'.
            totalOverdueTaskCount: contributions.reduce(into: Set<UUID>()) { partial, entry in
                partial.formUnion(entry.contribution.overdueTaskIDs)
            }.count,
            visibleGoals: visibleGoals
        )
    }

    nonisolated static func unavailableSnapshot(
        now: Date = Date(),
        message: String = "Open Cadence once to finish setting up shared widget data."
    ) -> CadenceMilestoneWidgetSnapshot {
        CadenceMilestoneWidgetSnapshot(
            date: now,
            state: .unavailable,
            statusMessage: message,
            totalGoalCount: 0,
            totalOverdueTaskCount: 0,
            visibleGoals: []
        )
    }

    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceMilestoneWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        switch snapshot.state {
        case .unavailable:
            return referenceDate.addingTimeInterval(5 * 60)
        case .empty:
            return referenceDate.addingTimeInterval(60 * 60)
        case .ready:
            return referenceDate.addingTimeInterval(30 * 60)
        }
    }

    static func prioritizedGoals(
        from goals: [Goal],
        now: Date = Date()
    ) -> [Goal] {
        prioritizedDecorations(from: goals, now: now).map(\.goal)
    }

    /// The ranked pool with the summaries the ranking used still attached.
    ///
    /// This is the shape `snapshot` needs and `prioritizedGoals` is now a projection of it. See
    /// `snapshot(from:now:limit:)` for why the summaries are carried rather than recomputed.
    static func prioritizedDecorations(
        from goals: [Goal],
        now: Date = Date()
    ) -> [CadenceMilestoneWidgetGoalDecoration] {
        ranked(activeContributions(from: goals, now: now), now: now)
    }

    /// One contribution walk per **active** goal — not per pool goal, because the overdue rollup
    /// counts directions that stepped out of the pool too. See `snapshot`'s note on the union.
    private static func activeContributions(
        from goals: [Goal],
        now: Date
    ) -> [(goal: Goal, contribution: GoalContributionSummary)] {
        goals
            .filter { $0.status == .active }
            .map { ($0, GoalContributionResolver.summary(for: $0, now: now)) }
    }

    private static func ranked(
        _ contributions: [(goal: Goal, contribution: GoalContributionSummary)],
        now: Date
    ) -> [CadenceMilestoneWidgetGoalDecoration] {
        // Decorated before sorting rather than resolved inside the comparator. Both resolvers
        // walk the goal's whole sub-tree, and a comparator runs O(n log n) times — so this was
        // four full tree walks per comparison, inside a widget timeline where the CPU and memory
        // budget is hard. Now it is one contribution and one momentum per goal, once.
        return contributions
            .filter { isInMilestonePool($0.goal) }
            .map { entry in
                CadenceMilestoneWidgetGoalDecoration(
                    goal: entry.goal,
                    contribution: entry.contribution,
                    momentum: GoalHabitMomentumResolver.summary(for: entry.goal, now: now)
                )
            }
            .sorted { lhsEntry, rhsEntry in
                let lhs = lhsEntry.goal
                let rhs = rhsEntry.goal
                let lhsSummary = lhsEntry.contribution
                let rhsSummary = rhsEntry.contribution
                let lhsMomentum = lhsEntry.momentum
                let rhsMomentum = rhsEntry.momentum

                if lhsSummary.overdueTaskCount != rhsSummary.overdueTaskCount {
                    return lhsSummary.overdueTaskCount > rhsSummary.overdueTaskCount
                }
                if lhsMomentum.dueTodayCount != rhsMomentum.dueTodayCount {
                    return lhsMomentum.dueTodayCount > rhsMomentum.dueTodayCount
                }

                let lhsEndDate = normalizedDate(lhs.endDate)
                let rhsEndDate = normalizedDate(rhs.endDate)
                if lhsEndDate != rhsEndDate {
                    return lhsEndDate < rhsEndDate
                }

                if lhsSummary.progress != rhsSummary.progress {
                    return lhsSummary.progress < rhsSummary.progress
                }
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return normalizedTitle(lhs.title) < normalizedTitle(rhs.title)
            }
    }

    /// The goals this widget ranks against each other: the **leaves** of the active goal tree.
    ///
    /// **T-355, a decision rather than a defect fix.** The pool used to be every active goal,
    /// parent and child alike. The app's Goals page is hierarchical — a top-level goal is a
    /// *direction* and renders as a header card above its milestones — and
    /// `GoalContributionResolver` recurses through sub-goals, so a direction's progress already
    /// contains its milestones'. Flattening both into one pool could therefore put a rollup and
    /// one of its own children side by side as peer "priority milestones", showing the child's
    /// progress twice to a reader with no way to see that they are the same work.
    ///
    /// The answer is to be genuinely milestone-first, which is what every string this widget draws
    /// already claims: "Milestone Momentum", "Priority milestone", "No active milestones", "Open
    /// Milestones". A goal is in the pool when no active goal is nested beneath it. A direction
    /// with live milestones steps aside for them; a goal with none — an un-nested goal, or a
    /// direction whose milestones are all done — *is* the leaf and stays.
    ///
    /// That last clause is why this is not simply `!goal.isTopLevel`. Filtering directions out
    /// wholesale would empty the widget for a user whose goals are not nested at all, while the
    /// app's own Goals page still shows them work — a widget going blank is a worse answer than
    /// the double count it was meant to fix.
    ///
    /// Descendants are walked recursively, not one level down. `GoalAssignmentRules` documents
    /// that goals nest exactly one level, but the editors enforce that, not the store, so a third
    /// level arriving over CloudKit must not put a middle goal back beside its own child.
    static func activeMilestonePool(from goals: [Goal]) -> [Goal] {
        goals.filter(isInMilestonePool)
    }

    /// The pool predicate, spelled once. `ranked` filters already-decorated entries with it rather
    /// than re-deriving the same two clauses, so the pool cannot come to mean two things.
    private static func isInMilestonePool(_ goal: Goal) -> Bool {
        goal.status == .active && !hasActiveDescendant(goal)
    }

    private static func hasActiveDescendant(_ goal: Goal) -> Bool {
        var visited: Set<UUID> = [goal.id]

        func walk(_ parent: Goal) -> Bool {
            for child in parent.subGoals ?? [] where visited.insert(child.id).inserted {
                if child.status == .active { return true }
                if walk(child) { return true }
            }
            return false
        }

        return walk(goal)
    }

    private static func widgetGoal(
        _ decoration: CadenceMilestoneWidgetGoalDecoration
    ) -> CadenceMilestoneWidgetGoal {
        let goal = decoration.goal
        let contribution = decoration.contribution
        let momentum = decoration.momentum
        return CadenceMilestoneWidgetGoal(
            id: goal.id,
            title: normalizedTitle(goal.title),
            colorHex: goal.colorHex,
            percentLabel: contribution.percentLabel,
            progress: contribution.progress,
            overdueTaskCount: contribution.overdueTaskCount,
            nextActionTitle: contribution.nextActionTitle,
            linkedHabitCount: momentum.linkedHabitCount,
            dueTodayLabel: momentum.dueTodayLabel,
            nextActionDueDate: contribution.nextActionDueDate ?? ""
        )
    }

    private nonisolated static func normalizedDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TaskOrdering.noDateSortKey : trimmed
    }

    private nonisolated static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Milestone" : trimmed
    }
}
