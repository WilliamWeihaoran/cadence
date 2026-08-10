import Foundation
import SwiftData

enum CadenceTrackingMutationSupport {
    /// `parentGoal == nil` creates a top-level direction (what used to be a pursuit);
    /// passing a parent nests this goal as a milestone of it.
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
        modelContext: ModelContext
    ) -> Goal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved = goal ?? Goal(title: trimmed)
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
        }

        try? modelContext.save()
        return resolved
    }

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
        modelContext: ModelContext
    ) -> Habit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved = habit ?? Habit(title: trimmed)
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
        }

        try? modelContext.save()
        return resolved
    }

    private static func nextOrder<T>(in items: [T], order: (T) -> Int) -> Int {
        (items.map(order).max() ?? -1) + 1
    }

    private static func nextOrder(in goals: [Goal]) -> Int {
        nextOrder(in: goals, order: \.order)
    }

    private static func nextOrder(in habits: [Habit]) -> Int {
        nextOrder(in: habits, order: \.order)
    }
}
