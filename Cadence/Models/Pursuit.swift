import SwiftData
import Foundation

/// RETIRED CONCEPT — kept only so `PursuitToGoalMigration` can read pre-merge data.
///
/// Pursuits were merged into `Goal`: a pursuit is now just a top-level goal (`parentGoal == nil`)
/// with `kind == .ongoing`, and the goals/habits it used to own hang off it via `parentGoal` /
/// `Habit.goal`. Nothing in the UI, navigation, search, or MCP surface references this model
/// any more — it exists solely so the one-time migration has something to migrate *from*.
///
/// Once the migration has run on every device that syncs this CloudKit container, this file,
/// the `Goal.pursuit` / `Habit.pursuit` / `Context.pursuits` relationships, and the schema entry
/// can all be deleted. See `PursuitToGoalMigration` for the removal checklist.
@Model final class Pursuit {
    var id: UUID = UUID()
    var title: String = ""
    var desc: String = ""
    var icon: String = "sparkles"
    var colorHex: String = "#a78bfa"
    var kindRaw: String = "ongoing"
    var statusRaw: String = "active"
    var order: Int = 0
    var createdAt: Date = Date()

    var kind: GoalKind {
        get { GoalKind(rawValue: kindRaw) ?? .ongoing }
        set { kindRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var context: Context? = nil
    @Relationship(inverse: \Goal.pursuit) var goals: [Goal]? = nil
    @Relationship(inverse: \Habit.pursuit) var habits: [Habit]? = nil

    init(title: String, context: Context? = nil, kind: GoalKind = .ongoing) {
        self.title = title
        self.context = context
        self.kindRaw = kind.rawValue
    }
}
