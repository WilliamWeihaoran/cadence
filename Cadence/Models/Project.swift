import SwiftData
import Foundation

/// Finite effort with a clear outcome and optional deadline.
@Model final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var status: String = "active"   // "active" | "done" | "paused" | "cancelled"
    var colorHex: String = "#4ecb71"
    var icon: String = "checklist"
    var dueDate: String = ""        // YYYY-MM-DD or ""
    var order: Int = 0
    var linkedCalendarID: String = ""   // EKCalendar identifier

    var context: Context? = nil
    var area: Area? = nil
    @Relationship(inverse: \AppTask.project) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Document.project) var documents: [Document]? = nil
    @Relationship(inverse: \SavedLink.project) var links: [SavedLink]? = nil

    var isDone: Bool { status == "done" }

    var completionRate: Double {
        let all = tasks ?? []
        let total = all.filter { $0.status != "cancelled" }.count
        guard total > 0 else { return 0 }
        return Double(all.filter { $0.isDone }.count) / Double(total)
    }

    init(name: String, context: Context? = nil, area: Area? = nil, colorHex: String = "#4ecb71") {
        self.name = name
        self.context = context
        self.area = area
        self.colorHex = colorHex
    }
}
