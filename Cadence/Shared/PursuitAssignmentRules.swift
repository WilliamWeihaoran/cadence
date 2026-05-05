import Foundation

enum PursuitAssignmentRules {
    static func canSaveMilestone(title: String, pursuitID: UUID?) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pursuitID != nil
    }

    static func canSaveGoal(title: String, pursuitID: UUID?) -> Bool {
        canSaveMilestone(title: title, pursuitID: pursuitID)
    }

    static func canSaveHabit(title: String, pursuitID: UUID?) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pursuitID != nil
    }

    static func unassignedMilestones(from goals: [Goal]) -> [Goal] {
        goals.filter { $0.pursuit == nil }
    }

    static func unassignedGoals(from goals: [Goal]) -> [Goal] {
        unassignedMilestones(from: goals)
    }

    static func unassignedHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { $0.pursuit == nil }
    }
}
