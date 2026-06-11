import Foundation
import SwiftData

enum CadenceTrackingMutationSupport {
    @discardableResult
    static func savePursuit(
        _ pursuit: Pursuit?,
        title: String,
        desc: String,
        icon: String,
        colorHex: String,
        kind: PursuitKind,
        status: PursuitStatus,
        context: Context?,
        allPursuits: [Pursuit],
        modelContext: ModelContext
    ) -> Pursuit? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolved = pursuit ?? Pursuit(title: trimmed)
        resolved.title = trimmed
        resolved.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        resolved.icon = icon
        resolved.colorHex = colorHex
        resolved.kind = kind
        resolved.status = status
        resolved.context = context

        if pursuit == nil {
            resolved.order = nextOrder(in: allPursuits)
            modelContext.insert(resolved)
        }

        try? modelContext.save()
        return resolved
    }

    @discardableResult
    static func saveGoal(
        _ goal: Goal?,
        title: String,
        desc: String,
        startDate: String,
        endDate: String,
        progressType: GoalProgressType,
        targetHours: Double,
        colorHex: String,
        status: GoalStatus,
        context: Context?,
        pursuit: Pursuit,
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
        resolved.colorHex = colorHex
        resolved.status = status
        resolved.context = context ?? pursuit.context
        resolved.pursuit = pursuit

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
        pursuit: Pursuit,
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
        resolved.context = context ?? pursuit.context
        resolved.pursuit = pursuit
        resolved.goal = goal

        if habit == nil {
            resolved.order = nextOrder(in: allHabits)
            modelContext.insert(resolved)
        }

        try? modelContext.save()
        return resolved
    }

    static func archivePursuit(_ pursuit: Pursuit, modelContext: ModelContext) {
        pursuit.status = .done
        try? modelContext.save()
    }

    static func archiveGoal(_ goal: Goal, modelContext: ModelContext) {
        goal.status = .done
        try? modelContext.save()
    }

    private static func nextOrder<T>(in items: [T], order: (T) -> Int) -> Int {
        (items.map(order).max() ?? -1) + 1
    }

    private static func nextOrder(in pursuits: [Pursuit]) -> Int {
        nextOrder(in: pursuits, order: \.order)
    }

    private static func nextOrder(in goals: [Goal]) -> Int {
        nextOrder(in: goals, order: \.order)
    }

    private static func nextOrder(in habits: [Habit]) -> Int {
        nextOrder(in: habits, order: \.order)
    }
}
