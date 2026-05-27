import Foundation
import SwiftData

enum CadenceHabitWidgetSnapshotState: String, Hashable {
    case ready
    case empty
    case unavailable
}

struct CadenceHabitWidgetHabit: Identifiable, Hashable {
    let id: UUID
    let title: String
    let icon: String
    let colorHex: String
    let frequencyLabel: String
    let currentStreak: Int
    let isDoneToday: Bool
}

struct CadenceHabitWidgetSnapshot: Hashable {
    let date: Date
    let dateKey: String
    let state: CadenceHabitWidgetSnapshotState
    let statusMessage: String?
    let totalDueCount: Int
    let doneCount: Int
    let habits: [CadenceHabitWidgetHabit]

    var habitsURL: URL {
        CadenceDeepLink.habits.url
    }

    var openCount: Int {
        max(totalDueCount - doneCount, 0)
    }

    var completionLabel: String {
        guard totalDueCount > 0 else { return "No habits due" }
        return "\(doneCount)/\(totalDueCount) checked in"
    }

    var isUnavailable: Bool {
        state == .unavailable
    }
}

enum CadenceHabitWidgetSupport {
    nonisolated static func snapshot(
        modelContext: ModelContext,
        limit: Int
    ) throws -> CadenceHabitWidgetSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Habit>()
        let habits = try modelContext.fetch(descriptor)
        return snapshot(from: habits, today: today, limit: limit)
    }

    nonisolated static func snapshot(
        from habits: [Habit],
        today: Date = Calendar.current.startOfDay(for: Date()),
        limit: Int,
        recentCompletionStates: [UUID: Bool]? = nil
    ) -> CadenceHabitWidgetSnapshot {
        let todayKey = CadenceWidgetDateSupport.dateKey(from: today)
        let recentStates = recentCompletionStates ?? CadenceWidgetRefreshCenter.recentHabitCompletionStates()
        let dueHabits = dueHabits(
            from: habits,
            today: today,
            recentCompletionStates: recentStates
        )
        let visibleHabits = Array(dueHabits.prefix(max(limit, 0))).map {
            widgetHabit(
                $0,
                todayKey: todayKey,
                recentCompletionStates: recentStates
            )
        }
        let doneCount = dueHabits.reduce(0) { partial, habit in
            partial + (isDoneToday(habit, todayKey: todayKey, recentCompletionStates: recentStates) ? 1 : 0)
        }

        return CadenceHabitWidgetSnapshot(
            date: today,
            dateKey: todayKey,
            state: dueHabits.isEmpty ? .empty : .ready,
            statusMessage: nil,
            totalDueCount: dueHabits.count,
            doneCount: doneCount,
            habits: visibleHabits
        )
    }

    nonisolated static func unavailableSnapshot(
        today: Date = Calendar.current.startOfDay(for: Date()),
        message: String = "Open Cadence once to finish setting up shared widget data."
    ) -> CadenceHabitWidgetSnapshot {
        CadenceHabitWidgetSnapshot(
            date: today,
            dateKey: CadenceWidgetDateSupport.dateKey(from: today),
            state: .unavailable,
            statusMessage: message,
            totalDueCount: 0,
            doneCount: 0,
            habits: []
        )
    }

    nonisolated static func recommendedReloadDate(
        for snapshot: CadenceHabitWidgetSnapshot,
        referenceDate: Date = Date()
    ) -> Date {
        let fallbackInterval: TimeInterval
        switch snapshot.state {
        case .unavailable:
            fallbackInterval = 5 * 60
        case .empty:
            fallbackInterval = 45 * 60
        case .ready:
            fallbackInterval = 20 * 60
        }

        let calendar = Calendar.current
        let nextStartOfDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        ).addingTimeInterval(60)
        return min(referenceDate.addingTimeInterval(fallbackInterval), nextStartOfDay)
    }

    nonisolated static func dueHabits(
        from habits: [Habit],
        today: Date = Calendar.current.startOfDay(for: Date()),
        recentCompletionStates: [UUID: Bool] = [:]
    ) -> [Habit] {
        let todayKey = CadenceWidgetDateSupport.dateKey(from: today)
        return habits
            .filter { $0.isDue(on: today) }
            .sorted { lhs, rhs in
                let lhsDone = isDoneToday(lhs, todayKey: todayKey, recentCompletionStates: recentCompletionStates)
                let rhsDone = isDoneToday(rhs, todayKey: todayKey, recentCompletionStates: recentCompletionStates)
                if lhsDone != rhsDone {
                    return !lhsDone && rhsDone
                }
                let lhsHasPursuit = lhs.pursuit != nil
                let rhsHasPursuit = rhs.pursuit != nil
                if lhsHasPursuit != rhsHasPursuit {
                    return lhsHasPursuit && !rhsHasPursuit
                }
                if lhs.currentStreak != rhs.currentStreak {
                    return lhs.currentStreak > rhs.currentStreak
                }
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return normalizedTitle(lhs.title) < normalizedTitle(rhs.title)
            }
    }

    private nonisolated static func widgetHabit(
        _ habit: Habit,
        todayKey: String,
        recentCompletionStates: [UUID: Bool]
    ) -> CadenceHabitWidgetHabit {
        CadenceHabitWidgetHabit(
            id: habit.id,
            title: normalizedTitle(habit.title),
            icon: habit.icon,
            colorHex: habit.colorHex,
            frequencyLabel: habit.frequencyShortLabel,
            currentStreak: habit.currentStreak,
            isDoneToday: isDoneToday(
                habit,
                todayKey: todayKey,
                recentCompletionStates: recentCompletionStates
            )
        )
    }

    private nonisolated static func isDoneToday(
        _ habit: Habit,
        todayKey: String,
        recentCompletionStates: [UUID: Bool]
    ) -> Bool {
        if let recentState = recentCompletionStates[habit.id] {
            return recentState
        }
        return habit.isDone(on: todayKey)
    }

    private nonisolated static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Habit" : trimmed
    }
}
