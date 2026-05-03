import Foundation

enum PursuitAssignmentRules {
    static func canSaveGoal(title: String, pursuitID: UUID?) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pursuitID != nil
    }

    static func canSaveHabit(title: String, pursuitID: UUID?) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pursuitID != nil
    }

    static func unassignedGoals(from goals: [Goal]) -> [Goal] {
        goals.filter { $0.pursuit == nil }
    }

    static func unassignedHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { $0.pursuit == nil }
    }
}
