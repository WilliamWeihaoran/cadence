import SwiftData
import Foundation

/// Ongoing responsibility with no definitive end date.
@Model final class Area {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var colorHex: String = "#4a9eff"
    var icon: String = "folder.fill"
    var order: Int = 0
    var linkedCalendarID: String = ""   // EKCalendar identifier for bidirectional sync

    var context: Context? = nil
    @Relationship(inverse: \AppTask.area) var tasks: [AppTask]? = nil
    @Relationship(inverse: \Project.area) var projects: [Project]? = nil
    @Relationship(inverse: \Document.area) var documents: [Document]? = nil
    @Relationship(inverse: \SavedLink.area) var links: [SavedLink]? = nil

    init(name: String, context: Context? = nil, colorHex: String = "#4a9eff", icon: String = "folder.fill") {
        self.name = name
        self.context = context
        self.colorHex = colorHex
        self.icon = icon
    }
}
