import SwiftData
import Foundation

/// A freeform note keyed by ISO week. One per week, auto-created.
@Model final class WeeklyNote {
    var id: UUID = UUID()
    var weekKey: String = ""    // "2026-W13"
    var content: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(weekKey: String) {
        self.weekKey = weekKey
    }
}
