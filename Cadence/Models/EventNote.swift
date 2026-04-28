import SwiftData
import Foundation

/// A markdown note linked directly to a calendar event by EKEvent identifier.
@Model final class EventNote {
    var id: UUID = UUID()
    var calendarEventID: String = ""
    var calendarID: String = ""
    var title: String = "Event Note"
    var content: String = ""
    var eventDateKey: String = ""
    var eventStartMin: Int = -1
    var eventEndMin: Int = -1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        calendarEventID: String,
        eventTitle: String,
        calendarID: String = "",
        eventDateKey: String = "",
        eventStartMin: Int = -1,
        eventEndMin: Int = -1
    ) {
        self.calendarEventID = calendarEventID
        self.calendarID = calendarID
        self.eventDateKey = eventDateKey
        self.eventStartMin = eventStartMin
        self.eventEndMin = eventEndMin
        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Event Note" : trimmedTitle
        self.title = resolvedTitle
        self.content = "# \(resolvedTitle)\n\n"
    }
}
