import SwiftData
import Foundation

@Model final class Goal {
    var id: UUID = UUID()
    var title: String = ""
    var desc: String = ""           // definitive outcome
    var startDate: String = ""      // YYYY-MM-DD
    var endDate: String = ""        // YYYY-MM-DD
    var progressType: String = "subtasks"  // "subtasks" | "hours"
    var targetHours: Double = 0
    var loggedHours: Double = 0     // manual + future timer data
    var colorHex: String = "#4a9eff"
    var status: String = "active"   // "active" | "done" | "paused"
    var order: Int = 0
    var createdAt: Date = Date()

    var context: Context? = nil
    @Relationship(inverse: \AppTask.goal) var tasks: [AppTask]? = nil

    // Future TODO: sub-goals (parent/children relationship)

    var progress: Double {
        switch progressType {
        case "hours":
            guard targetHours > 0 else { return 0 }
            return min(1.0, loggedHours / targetHours)
        case "subtasks":
            let all = (tasks ?? []).filter { !$0.isCancelled }
            guard !all.isEmpty else { return 0 }
            return Double(all.filter { $0.isDone }.count) / Double(all.count)
        default: return 0
        }
    }

    init(title: String, context: Context? = nil) {
        self.title = title
        self.context = context
    }
}
