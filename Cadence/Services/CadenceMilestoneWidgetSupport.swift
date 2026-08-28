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

nonisolated enum CadenceMilestoneWidgetSupport {
    static func snapshot(
        modelContext: ModelContext,
        limit: Int
    ) throws -> CadenceMilestoneWidgetSnapshot {
        let descriptor = FetchDescriptor<Goal>()
        let goals = try modelContext.fetch(descriptor)
        return snapshot(from: goals, now: Date(), limit: limit)
    }

    static func snapshot(
        from goals: [Goal],
        now: Date = Date(),
        limit: Int
    ) -> CadenceMilestoneWidgetSnapshot {
        let pool = prioritizedGoals(from: goals, now: now)
        let visibleGoals = Array(pool.prefix(max(limit, 0))).map { widgetGoal($0, now: now) }
        let activeGoals = goals.filter { $0.status == .active }

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
            totalOverdueTaskCount: activeGoals.reduce(into: Set<UUID>()) { partial, goal in
                partial.formUnion(GoalContributionResolver.overdueTasks(for: goal, now: now).map(\.id))
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
        // Decorated before sorting rather than resolved inside the comparator. Both resolvers
        // walk the goal's whole sub-tree, and a comparator runs O(n log n) times — so this was
        // four full tree walks per comparison, inside a widget timeline where the CPU and memory
        // budget is hard. Now it is two per goal, once.
        let decorated = activeMilestonePool(from: goals)
            .map { goal in
                (
                    goal: goal,
                    summary: GoalContributionResolver.summary(for: goal, now: now),
                    momentum: GoalHabitMomentumResolver.summary(for: goal, now: now)
                )
            }

        return decorated
            .sorted { lhsEntry, rhsEntry in
                let lhs = lhsEntry.goal
                let rhs = rhsEntry.goal
                let lhsSummary = lhsEntry.summary
                let rhsSummary = rhsEntry.summary
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
            .map(\.goal)
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
        goals.filter { $0.status == .active && !hasActiveDescendant($0) }
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
        _ goal: Goal,
        now: Date
    ) -> CadenceMilestoneWidgetGoal {
        let contribution = GoalContributionResolver.summary(for: goal, now: now)
        let momentum = GoalHabitMomentumResolver.summary(for: goal, now: now)
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
