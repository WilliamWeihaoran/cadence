import Foundation
import SwiftData

enum NoteKind: String, CaseIterable {
    case daily
    case weekly
    case permanent
    case list
    case meeting
}

@Model final class Note {
    var id: UUID = UUID()
    var kindRaw: String = NoteKind.list.rawValue
    var title: String = "Untitled"
    var content: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var dateKey: String = ""
    var weekKey: String = ""

    var calendarEventID: String = ""
    var calendarID: String = ""
    var eventDateKey: String = ""
    var eventStartMin: Int = -1
    var eventEndMin: Int = -1

    var legacySourceKindRaw: String = ""
    var legacySourceID: String = ""

    var area: Area? = nil
    var project: Project? = nil
    var tags: [Tag]? = nil

    var kind: NoteKind {
        get { NoteKind(rawValue: kindRaw) ?? .list }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: NoteKind,
        title: String = "Untitled",
        content: String = "",
        order: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dateKey: String = "",
        weekKey: String = "",
        calendarEventID: String = "",
        calendarID: String = "",
        eventDateKey: String = "",
        eventStartMin: Int = -1,
        eventEndMin: Int = -1,
        legacySourceKind: String = "",
        legacySourceID: String = "",
        area: Area? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.content = content
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dateKey = dateKey
        self.weekKey = weekKey
        self.calendarEventID = calendarEventID
        self.calendarID = calendarID
        self.eventDateKey = eventDateKey
        self.eventStartMin = eventStartMin
        self.eventEndMin = eventEndMin
        self.legacySourceKindRaw = legacySourceKind
        self.legacySourceID = legacySourceID
        self.area = area
        self.project = project
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch kind {
        case .daily:
            return dateKey.isEmpty ? "Daily Note" : dateKey
        case .weekly:
            return weekKey.isEmpty ? "Weekly Note" : weekKey
        case .permanent:
            return "Notepad"
        case .list:
            return "Untitled"
        case .meeting:
            return "Event Note"
        }
    }

    var sortedTags: [Tag] {
        TagSupport.sorted(tags ?? [])
    }
}
