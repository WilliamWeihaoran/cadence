import Foundation
import SwiftData

nonisolated enum NoteKind: String, CaseIterable {
    case daily
    case weekly
    case permanent
    case list
    case meeting

    /// Whether this kind's title follows its first `# H1`.
    ///
    /// Declared here rather than on `MarkdownNoteTitleSync` because it is a fact about the kind,
    /// and `DataIntegrityRepairService` -- which the MCP server target compiles -- needs it while
    /// `MarkdownNoteSupport.swift` is not in that target's explicit source list. T-741 called
    /// across that boundary and broke the MCP build in a way no app-scheme run could see;
    /// `mcpServerSourcesOnlyReferenceTypesThatTargetCompiles` is what caught it.
    var syncsTitleFromH1: Bool { self == .list || self == .permanent }
}

@Model final class Note {
    var id: UUID = UUID()
    var kindRaw: String = NoteKind.list.rawValue

    /// **Empty by default, and that is a decision (T-733).**
    ///
    /// This defaulted to the literal `"Untitled"`, which made the word *stored text* rather than a
    /// placeholder: a new notepad note was seeded `"# Untitled\n\n"` from it, the editor put the
    /// caret after the heading, and typing `Target` produced `UntitledTarget` — observed on a
    /// simulator on 2026-09-02.
    ///
    /// Nothing needed the stored default to begin with. `displayTitle` below already falls back per
    /// kind — `"Notepad"` for `.permanent`, the date key for `.daily`, `"Untitled"` for `.list` —
    /// so the default was redundant as well as in the way, and it shadowed every one of those
    /// fallbacks by never being blank.
    ///
    /// Rows already holding the literal are cleared by
    /// `DataIntegrityRepairService.repairStoredDefaultNoteTitles`, at load rather than by a schema
    /// migration: this project has no `SchemaMigrationPlan`, and a property *default* is not
    /// persisted anyway — it applies to rows this build creates, never to rows already on disk.
    var title: String = ""
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
    var folderPath: String = ""

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
        title: String = "",
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
        folderPath: String = "",
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
        self.folderPath = folderPath
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

    /// The identity two notes have to share before anything is allowed to treat them as the same
    /// note — one daily note per day, one weekly note per ISO week, one notepad, one note per
    /// calendar event. List notes are identified only by themselves: two list notes on the same
    /// project are two different documents.
    ///
    /// This existed twice, and the two copies **disagreed**: `NoteMigrationService.canonicalKey`
    /// keyed every dateless daily note as `"daily:"` while `DataIntegrityRepairService`
    /// `canonicalNoteKey` gave each one a per-UUID key, and only the repair copy trimmed
    /// whitespace. So the migration collapsed all dateless daily notes into one key — skipping
    /// real legacy rows as "already migrated" and reporting phantom duplicates — while the repair
    /// pass looked at the same rows and refused to merge them. Two passes over the same store
    /// reached opposite conclusions.
    ///
    /// The trimming, per-UUID-fallback behaviour is the one kept: a note with no date key has no
    /// shared identity to collide on, and a key that only differs by whitespace is the same key.
    ///
    /// `nonisolated` because the migration and repair services reach it from nonisolated contexts,
    /// and this module defaults to `MainActor` isolation.
    nonisolated var canonicalKey: String {
        Note.canonicalKey(
            kind: kind,
            dateKey: dateKey,
            weekKey: weekKey,
            calendarEventID: calendarEventID,
            id: id
        )
    }

    /// Field-wise form of `canonicalKey`, so the migration can ask what key a *legacy* row would
    /// produce before the `Note` that replaces it exists. Migration inserts each note with
    /// `id: legacy.id`, so the per-UUID fallbacks line up.
    nonisolated static func canonicalKey(
        kind: NoteKind,
        dateKey: String = "",
        weekKey: String = "",
        calendarEventID: String = "",
        id: UUID
    ) -> String {
        func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch kind {
        case .daily:
            let key = trimmed(dateKey)
            return key.isEmpty ? "daily-note:\(id.uuidString)" : "daily:\(key)"
        case .weekly:
            let key = trimmed(weekKey)
            return key.isEmpty ? "weekly-note:\(id.uuidString)" : "weekly:\(key)"
        case .permanent:
            return "permanent"
        case .list:
            return "list:\(id.uuidString)"
        case .meeting:
            let key = trimmed(calendarEventID)
            return key.isEmpty ? "meeting-note:\(id.uuidString)" : "meeting:\(key)"
        }
    }
}
