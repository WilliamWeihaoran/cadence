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
    var statusRaw: String = "active"

    var progressType: GoalProgressType {
        get { GoalProgressType(rawValue: progressTypeRaw) ?? .subtasks }
        set { progressTypeRaw = newValue.rawValue }
    }
    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var order: Int = 0
    var createdAt: Date = Date()

    var context: Context? = nil
    @Relationship(inverse: \AppTask.goal) var tasks: [AppTask]? = nil

    // Future TODO: sub-goals (parent/children relationship)

    var progress: Double {
        switch progressType {
        case .hours:
            guard targetHours > 0 else { return 0 }
            return min(1.0, loggedHours / targetHours)
        case .subtasks:
            let all = (tasks ?? []).filter { !$0.isCancelled }
            guard !all.isEmpty else { return 0 }
            return Double(all.filter { $0.isDone }.count) / Double(all.count)
        }
    }

    init(title: String, context: Context? = nil) {
        self.title = title
        self.context = context
    }
}
