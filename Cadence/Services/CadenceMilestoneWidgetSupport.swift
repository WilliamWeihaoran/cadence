import Foundation
import SwiftData

enum CadenceMilestoneWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

struct CadenceMilestoneWidgetGoal: Identifiable, Hashable {
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

struct CadenceMilestoneWidgetSnapshot: Hashable {
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

enum CadenceMilestoneWidgetSupport {
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
        let activeGoals = prioritizedGoals(from: goals, now: now)
        let visibleGoals = Array(activeGoals.prefix(max(limit, 0))).map { widgetGoal($0, now: now) }

        return CadenceMilestoneWidgetSnapshot(
            date: now,
            state: activeGoals.isEmpty ? .empty : .ready,
            statusMessage: nil,
            totalGoalCount: activeGoals.count,
            totalOverdueTaskCount: activeGoals.reduce(0) { partial, goal in
                partial + GoalContributionResolver.summary(for: goal, now: now).overdueTaskCount
            },
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
        goals
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                let lhsSummary = GoalContributionResolver.summary(for: lhs, now: now)
                let rhsSummary = GoalContributionResolver.summary(for: rhs, now: now)
                let lhsMomentum = GoalHabitMomentumResolver.summary(for: lhs, now: now)
                let rhsMomentum = GoalHabitMomentumResolver.summary(for: rhs, now: now)

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
        return trimmed.isEmpty ? "9999-12-31" : trimmed
    }

    private nonisolated static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Milestone" : trimmed
    }
}
