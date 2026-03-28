import SwiftData
import Foundation

/// A date-keyed freeform note. One per day, auto-created.
@Model final class DailyNote {
    var id: UUID = UUID()
    var date: String = ""       // YYYY-MM-DD — primary key by convention
    var content: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(date: String) {
        self.date = date
    }
}
