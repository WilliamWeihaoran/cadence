import SwiftData
import Foundation

/// Directional effort under a top-level context. Holds finishable goals and recurring habits.
@Model final class Pursuit {
    var id: UUID = UUID()
    var title: String = ""
    var desc: String = ""
    var icon: String = "sparkles"
    var colorHex: String = "#a78bfa"
    var statusRaw: String = "active"
    var order: Int = 0
    var createdAt: Date = Date()

    var status: PursuitStatus {
        get { PursuitStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var context: Context? = nil
    @Relationship(inverse: \Goal.pursuit) var goals: [Goal]? = nil
    @Relationship(inverse: \Habit.pursuit) var habits: [Habit]? = nil

    init(title: String, context: Context? = nil) {
        self.title = title
        self.context = context
    }
}
