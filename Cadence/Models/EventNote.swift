import SwiftData
import Foundation

/// A markdown note linked directly to a calendar event by EKEvent identifier.
@Model final class EventNote {
    var id: UUID = UUID()
    var calendarEventID: String = ""
    var title: String = "Event Note"
    var content: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(calendarEventID: String, eventTitle: String) {
        self.calendarEventID = calendarEventID
        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Event Note" : trimmedTitle
        self.title = resolvedTitle
        self.content = "# \(resolvedTitle)\n\n"
    }
}
