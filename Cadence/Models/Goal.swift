import SwiftData
import Foundation

@Model final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var desc: String = ""           // definitive outcome
    var startDate: String = ""      // YYYY-MM-DD
    var endDate: String = ""        // YYYY-MM-DD
    var progressTypeRaw: String = "subtasks"
    var targetHours: Double = 0
    var loggedHours: Double = 0     // manual + future timer data
    var colorHex: String = "#4a9eff"
    var icon: String = "flag.fill"
    var statusRaw: String = "active"
    /// Defaults to `.completable` so every pre-existing goal keeps reading as a milestone.
    /// Goals migrated up from the retired `Pursuit` model carry their original kind.
    var kindRaw: String = "completable"

    var progressType: GoalProgressType {
        get { GoalProgressType(rawValue: progressTypeRaw) ?? .subtasks }
        set { progressTypeRaw = newValue.rawValue }
    }
    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .completable }
        set { kindRaw = newValue.rawValue }
    }

    /// A goal with no parent is a top-level direction; nested goals read as its milestones.
    var isTopLevel: Bool { parentGoal == nil }
    var order: Int = 0
    var createdAt: Date = Date()
    // Dependency IDs stored as JSON array of UUID strings (finish-to-start: this goal depends on listed goals)
    var dependsOnGoalIDsJSON: String = ""

    var context: Context? = nil
    var pursuit: Pursuit? = nil
    var parentGoal: Goal? = nil
    @Relationship(deleteRule: .nullify, inverse: \Goal.parentGoal) var subGoals: [Goal]? = nil
    @Relationship(inverse: \AppTask.goal) var tasks: [AppTask]? = nil
    @Relationship(inverse: \GoalListLink.goal) var listLinks: [GoalListLink]? = nil
    @Relationship(inverse: \Habit.goal) var habits: [Habit]? = nil

    var progress: Double {
        GoalContributionResolver.summary(for: self).progress
    }

    init(title: String, context: Context? = nil) {
        self.title = title
        self.context = context
    }
}
